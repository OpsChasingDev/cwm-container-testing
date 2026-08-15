#!/usr/bin/env bash
# Tear down cost tiers. Each tier is independent and has a matching up.sh tier.
#
#   ./down.sh 1     stop all running container groups            ~$32-40/mo
#   ./down.sh 2     ACR Standard -> Basic                        ~$15/mo
#   ./down.sh 3     delete container groups                       $0 extra (hygiene)
#   ./down.sh 4     archive images, delete the registry          ~$5/mo  (after t2)
#   ./down.sh 5     delete DNS zone                              ~$0.50/mo
#   ./down.sh 6     delete the whole resource group              remaining ~$0.01/mo
#   ./down.sh 1 2   run several tiers in order
#
# ASSUME_YES=1 skips the prompts (for cron / CI).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_az
[[ $# -gt 0 ]] || die "usage: down.sh <tier> [tier...]   (tiers 1-6)"

tier1_stop_containers() {
  log "Tier 1 — stopping running container groups"
  local any=0
  for g in $(aci_groups); do
    local s; s="$(aci_state "$g")"
    if [[ "$s" == "Running" ]]; then
      az_ container stop -g "$RESOURCE_GROUP" -n "$g"
      ok "stopped $g"
      any=1
    else
      printf '     skip %s (%s)\n' "$g" "$s"
    fi
  done
  [[ $any == 1 ]] || ok "nothing was running"
  warn "stopping releases the public IP — up.sh 1 re-points DNS after restart"
}

tier2_acr_basic() {
  local sku; sku="$(acr_sku)"
  log "Tier 2 — ACR sku $sku -> Basic"
  [[ "$sku" == "Absent" ]] && { warn "registry already gone"; return 0; }
  [[ "$sku" == "Basic" ]] && { ok "already Basic"; return 0; }
  local used_gb
  used_gb="$(az_ acr show-usage -n "$ACR_NAME" \
    --query "value[?name=='Size'].currentValue | [0]" -o tsv)"
  used_gb=$(( used_gb / 1073741824 ))
  (( used_gb < 10 )) || die "registry uses ${used_gb}GB, over Basic's 10GB included quota"
  az_ acr update -n "$ACR_NAME" --sku Basic >/dev/null
  ok "ACR now Basic (${used_gb}GB used of 10GB included)"
}

tier3_delete_containers() {
  require_state
  log "Tier 3 — deleting container groups"
  warn "stopped container groups already cost \$0 — this is cleanup, not savings"
  confirm "Delete all $( aci_groups | wc -l | tr -d ' ') container groups in $RESOURCE_GROUP?"
  for g in $(aci_groups); do
    [[ -f "$STATE_DIR/aci/$g.json" ]] \
      || die "no captured state for $g — re-run capture-state.sh"
    az_ container delete -g "$RESOURCE_GROUP" -n "$g" --yes >/dev/null
    ok "deleted $g"
  done
}

tier4_archive_and_delete_acr() {
  require_state
  local sku; sku="$(acr_sku)"
  [[ "$sku" == "Absent" ]] && { ok "registry already gone"; return 0; }

  local tagfile="$STATE_DIR/acr/_deployed_tags.tsv"
  [[ "${ARCHIVE_TAGS:-deployed}" == "all" ]] && tagfile="$STATE_DIR/acr/_tags.tsv"
  local n; n="$(wc -l < "$tagfile" | tr -d ' ')"

  log "Tier 4 — archiving $n image tags, then deleting registry $ACR_NAME"
  command -v docker >/dev/null || die "docker required to archive images"
  docker info >/dev/null 2>&1 || die "docker daemon not running"

  local server; server="$(acr_login_server)"
  local archive="$STATE_DIR/acr/images"
  mkdir -p "$archive"
  az_ acr login -n "$ACR_NAME" >/dev/null

  while IFS=$'\t' read -r repo tag; do
    [[ -n "$repo" ]] || continue
    local out="$archive/${repo}__${tag}.tar"
    [[ -f "$out.gz" ]] && { printf '     have %s:%s\n' "$repo" "$tag"; continue; }
    docker pull "$server/$repo:$tag" >/dev/null
    docker save "$server/$repo:$tag" -o "$out"
    gzip -f "$out"
    ok "archived $repo:$tag"
  done < "$tagfile"

  printf '%s\n' "$server" > "$STATE_DIR/acr/_login_server"
  confirm "Archive complete in $archive. Delete registry $ACR_NAME now?"
  az_ acr delete -n "$ACR_NAME" --yes >/dev/null
  ok "deleted registry $ACR_NAME"
  warn "a recreated registry gets a NEW login server suffix — update the ACR_LOGIN_SERVER"
  warn "GitHub secret and any pinned image references after up.sh 4"
}

tier5_delete_dns() {
  require_state
  log "Tier 5 — deleting DNS zone $DNS_ZONE (~\$0.50/mo)"
  warn "recreating the zone yields NEW nameservers; the NS delegation for"
  warn "'$PARENT_DNS_CHILD' in $PARENT_DNS_ZONE ($PARENT_DNS_RG / sub $PARENT_DNS_SUB)"
  warn "must be updated afterwards. up.sh 5 does that for you."
  confirm "Delete DNS zone $DNS_ZONE?"
  az_ network dns zone delete -g "$RESOURCE_GROUP" -n "$DNS_ZONE" --yes >/dev/null
  ok "deleted zone $DNS_ZONE"
}

tier6_delete_rg() {
  require_state
  log "Tier 6 — deleting resource group $RESOURCE_GROUP"
  warn "this destroys the storage account and every report/log file on the shares"
  warn "run scripts/cost/archive-shares.sh first if that data matters"
  confirm "PERMANENTLY delete resource group $RESOURCE_GROUP and everything in it?"
  az_ group delete -n "$RESOURCE_GROUP" --yes --no-wait
  ok "delete submitted (async) — subscription run rate goes to \$0"
}

for tier in "$@"; do
  case "$tier" in
    1) tier1_stop_containers ;;
    2) tier2_acr_basic ;;
    3) tier3_delete_containers ;;
    4) tier4_archive_and_delete_acr ;;
    5) tier5_delete_dns ;;
    6) tier6_delete_rg ;;
    *) die "unknown tier '$tier' (valid: 1-6)" ;;
  esac
done
