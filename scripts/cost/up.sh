#!/usr/bin/env bash
# Reverse down.sh, tier by tier. Restore in DESCENDING tier order:
# the registry must exist before container groups can pull, and the resource
# group must exist before anything.
#
#   ./up.sh 6      recreate the resource group
#   ./up.sh 5      recreate the DNS zone + records + parent NS delegation
#   ./up.sh 4      recreate the registry and push archived images back
#   ./up.sh 3      recreate all container groups from captured state
#   ./up.sh 2      ACR Basic -> Standard
#   ./up.sh 1      start container groups + re-point DNS at the new web IP
#
# Full rebuild from nothing:  ./up.sh 6 5 4 3 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_az
[[ $# -gt 0 ]] || die "usage: up.sh <tier> [tier...]   (tiers 1-6)"

RENDER="$(dirname "${BASH_SOURCE[0]}")/render-aci-yaml.py"

# Point DNS at whatever public IP the web container currently holds.
# ACI assigns a new IP on every start, so this must run after every tier-1 start.
sync_web_dns() {
  local group="$1" record
  case "$group" in
    cwm-prod-web)    record="@" ;;
    cwm-staging-web) record="staging" ;;
    *) return 0 ;;
  esac
  local ip
  ip="$(az_ container show -g "$RESOURCE_GROUP" -n "$group" \
        --query "ipAddress.ip" -o tsv 2>/dev/null || true)"
  [[ -n "$ip" && "$ip" != "None" ]] || { warn "$group has no public IP yet — skipping DNS"; return 0; }

  az_ network dns record-set a delete -g "$RESOURCE_GROUP" -z "$DNS_ZONE" \
    -n "$record" --yes >/dev/null 2>&1 || true
  az_ network dns record-set a create -g "$RESOURCE_GROUP" -z "$DNS_ZONE" \
    -n "$record" --ttl 60 >/dev/null
  az_ network dns record-set a add-record -g "$RESOURCE_GROUP" -z "$DNS_ZONE" \
    --record-set-name "$record" --ipv4-address "$ip" >/dev/null
  ok "dns $record.$DNS_ZONE -> $ip"
}

tier1_start_containers() {
  require_state
  log "Tier 1 — starting container groups that were running at capture time"
  local started=()
  while IFS=$'\t' read -r g s; do
    [[ -n "$g" ]] || continue
    if [[ "${START_ALL:-0}" == "1" || "$s" == "Running" ]]; then
      az_ container start -g "$RESOURCE_GROUP" -n "$g" >/dev/null
      ok "started $g"
      started+=("$g")
    else
      printf '     skip %s (was %s at capture)\n' "$g" "$s"
    fi
  done < "$STATE_DIR/aci/_manifest.tsv"
  for g in "${started[@]:-}"; do
    [[ -n "$g" ]] && sync_web_dns "$g"
  done
}

tier2_acr_standard() {
  local sku; sku="$(acr_sku)"
  log "Tier 2 — ACR sku $sku -> Standard"
  [[ "$sku" == "Absent" ]] && die "registry does not exist — run up.sh 4 first"
  [[ "$sku" == "Standard" ]] && { ok "already Standard"; return 0; }
  az_ acr update -n "$ACR_NAME" --sku Standard >/dev/null
  ok "ACR now Standard"
}

tier3_recreate_containers() {
  require_state
  command -v python3 >/dev/null || die "python3 required to render deployment YAML"
  [[ "$(acr_sku)" != "Absent" ]] || die "registry missing — run up.sh 4 first"

  log "Tier 3 — recreating container groups from $STATE_DIR/aci"
  local pw key tmp
  pw="$(acr_password)"
  key="$(storage_key)"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  while IFS=$'\t' read -r g s; do
    [[ -n "$g" ]] || continue
    local src="$STATE_DIR/aci/$g.json"
    [[ -f "$src" ]] || { warn "no capture for $g — skipping"; continue; }
    python3 "$RENDER" "$src" --acr-password "$pw" --storage-key "$key" > "$tmp/$g.yaml"
    az_ container delete -g "$RESOURCE_GROUP" -n "$g" --yes >/dev/null 2>&1 || true
    az_ container create -g "$RESOURCE_GROUP" --file "$tmp/$g.yaml" >/dev/null
    ok "recreated $g"
    sync_web_dns "$g"
  done < "$STATE_DIR/aci/_manifest.tsv"

  warn "container groups start Running on create — run down.sh 1 to park them again"
}

tier4_recreate_acr() {
  require_state
  log "Tier 4 — recreating registry $ACR_NAME and restoring archived images"
  if [[ "$(acr_sku)" == "Absent" ]]; then
    az_ acr create -g "$RESOURCE_GROUP" -n "$ACR_NAME" \
      --sku "${ACR_RESTORE_SKU:-Basic}" --admin-enabled true -l "$LOCATION" >/dev/null
    ok "created registry ($( az_ acr show -n "$ACR_NAME" --query sku.name -o tsv ))"
  else
    ok "registry already exists"
  fi

  local new_server old_server archive
  new_server="$(acr_login_server)"
  old_server="$(cat "$STATE_DIR/acr/_login_server" 2>/dev/null || echo "")"
  archive="$STATE_DIR/acr/images"

  if [[ "$new_server" != "$old_server" && -n "$old_server" ]]; then
    warn "login server changed: $old_server -> $new_server"
    warn "update the ACR_LOGIN_SERVER GitHub secret to $new_server"
  fi

  [[ -d "$archive" ]] || { warn "no image archive at $archive — rebuild via GitHub Actions instead"; return 0; }
  command -v docker >/dev/null || die "docker required to restore images"
  az_ acr login -n "$ACR_NAME" >/dev/null

  for f in "$archive"/*.tar.gz; do
    [[ -e "$f" ]] || continue
    local base repo tag
    base="$(basename "$f" .tar.gz)"
    repo="${base%%__*}"
    tag="${base#*__}"
    gunzip -c "$f" | docker load >/dev/null
    docker tag "$old_server/$repo:$tag" "$new_server/$repo:$tag" 2>/dev/null || true
    docker push "$new_server/$repo:$tag" >/dev/null
    ok "restored $repo:$tag"
  done
}

tier5_recreate_dns() {
  require_state
  log "Tier 5 — recreating DNS zone $DNS_ZONE"
  az_ network dns zone show -g "$RESOURCE_GROUP" -n "$DNS_ZONE" >/dev/null 2>&1 \
    || az_ network dns zone create -g "$RESOURCE_GROUP" -n "$DNS_ZONE" >/dev/null
  ok "zone present"

  # Replay non-authority record sets from the capture.
  python3 - "$STATE_DIR/dns/recordsets.json" <<'PY' > /tmp/dns-replay.sh
import json, sys, shlex
rs = json.load(open(sys.argv[1]))
for r in rs:
    t = r["type"].rsplit("/", 1)[-1]
    if t in ("SOA", "NS") and r["name"] == "@":
        continue          # zone authority records are managed by Azure
    if t == "A":
        for a in r.get("aRecords") or []:
            print(f'aci_a {shlex.quote(r["name"])} {shlex.quote(a["ipv4Address"])} {r.get("ttl",60)}')
    elif t == "CNAME" and r.get("cnameRecord"):
        print(f'aci_cname {shlex.quote(r["name"])} {shlex.quote(r["cnameRecord"]["cname"])} {r.get("ttl",60)}')
    elif t == "TXT":
        for v in r.get("txtRecords") or []:
            print(f'aci_txt {shlex.quote(r["name"])} {shlex.quote("".join(v["value"]))} {r.get("ttl",60)}')
PY

  aci_a()     { az_ network dns record-set a create  -g "$RESOURCE_GROUP" -z "$DNS_ZONE" -n "$1" --ttl "$3" >/dev/null 2>&1 || true
                az_ network dns record-set a add-record -g "$RESOURCE_GROUP" -z "$DNS_ZONE" --record-set-name "$1" --ipv4-address "$2" >/dev/null; ok "A $1 -> $2"; }
  aci_cname() { az_ network dns record-set cname set-record -g "$RESOURCE_GROUP" -z "$DNS_ZONE" -n "$1" -c "$2" --ttl "$3" >/dev/null; ok "CNAME $1 -> $2"; }
  aci_txt()   { az_ network dns record-set txt add-record -g "$RESOURCE_GROUP" -z "$DNS_ZONE" -n "$1" -v "$2" >/dev/null; ok "TXT $1"; }
  # shellcheck disable=SC1091
  source /tmp/dns-replay.sh
  rm -f /tmp/dns-replay.sh

  # Re-delegate from the parent zone (different subscription).
  log "Updating NS delegation in $PARENT_DNS_ZONE"
  local ns
  ns="$(az_ network dns zone show -g "$RESOURCE_GROUP" -n "$DNS_ZONE" \
        --query "nameServers" -o tsv)"
  az_parent_ network dns record-set ns delete \
    -g "$PARENT_DNS_RG" -z "$PARENT_DNS_ZONE" -n "$PARENT_DNS_CHILD" --yes >/dev/null 2>&1 || true
  az_parent_ network dns record-set ns create \
    -g "$PARENT_DNS_RG" -z "$PARENT_DNS_ZONE" -n "$PARENT_DNS_CHILD" --ttl 3600 >/dev/null
  while read -r n; do
    [[ -n "$n" ]] || continue
    az_parent_ network dns record-set ns add-record \
      -g "$PARENT_DNS_RG" -z "$PARENT_DNS_ZONE" --record-set-name "$PARENT_DNS_CHILD" \
      --nsdname "$n" >/dev/null
    ok "delegation NS $n"
  done <<< "$ns"
}

tier6_recreate_rg() {
  log "Tier 6 — recreating resource group and storage"
  az_ group create -n "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null
  ok "resource group $RESOURCE_GROUP"

  require_state
  az_ storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" >/dev/null 2>&1 \
    || az_ storage account create -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" \
         -l "$LOCATION" --sku Standard_LRS --kind StorageV2 >/dev/null
  ok "storage account $STORAGE_ACCOUNT"

  python3 -c "
import json,sys
for s in json.load(open('$STATE_DIR/storage/shares.json')):
    print(s['name'], s.get('shareQuota', 5120))
" | while read -r name quota; do
    az_ storage share-rm create -g "$RESOURCE_GROUP" \
      --storage-account "$STORAGE_ACCOUNT" -n "$name" --quota "$quota" >/dev/null 2>&1 || true
    ok "share $name (${quota}GB quota)"
  done
  warn "share CONTENTS are not restored here — see scripts/cost/archive-shares.sh"
}

for tier in "$@"; do
  case "$tier" in
    1) tier1_start_containers ;;
    2) tier2_acr_standard ;;
    3) tier3_recreate_containers ;;
    4) tier4_recreate_acr ;;
    5) tier5_recreate_dns ;;
    6) tier6_recreate_rg ;;
    *) die "unknown tier '$tier' (valid: 1-6)" ;;
  esac
done
