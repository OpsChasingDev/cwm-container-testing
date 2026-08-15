#!/usr/bin/env bash
# Snapshot everything needed to rebuild this project's Azure footprint.
# Run this BEFORE any destructive tier. Output lands in .infra-state/ (gitignored).
#
# WARNING: the captured container-group JSON contains the CWM API keys in
# plaintext, because they are stored as plain ACI environment variables.
# .infra-state/ must never be committed or shared.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_az

mkdir -p "$STATE_DIR/aci" "$STATE_DIR/acr" "$STATE_DIR/dns" "$STATE_DIR/storage"
chmod 700 "$STATE_DIR"

log "Capturing state to $STATE_DIR"

# --- 1. Container groups ------------------------------------------------------
: > "$STATE_DIR/aci/_manifest.tsv"
for g in $(aci_groups); do
  az_ container show -g "$RESOURCE_GROUP" -n "$g" -o json > "$STATE_DIR/aci/$g.json"
  state="$(az_ container show -g "$RESOURCE_GROUP" -n "$g" \
            --query "instanceView.state" -o tsv 2>/dev/null || echo Unknown)"
  printf '%s\t%s\n' "$g" "$state" >> "$STATE_DIR/aci/_manifest.tsv"
  ok "aci  $g ($state)"
done

# --- 2. Container registry ----------------------------------------------------
if [[ "$(acr_sku)" != "Absent" ]]; then
  az_ acr show -n "$ACR_NAME" -o json > "$STATE_DIR/acr/registry.json"
  : > "$STATE_DIR/acr/_tags.tsv"
  for repo in $(az_ acr repository list -n "$ACR_NAME" -o tsv); do
    for tag in $(az_ acr repository show-tags -n "$ACR_NAME" --repository "$repo" -o tsv); do
      printf '%s\t%s\n' "$repo" "$tag" >> "$STATE_DIR/acr/_tags.tsv"
    done
  done
  ok "acr  $ACR_NAME ($(acr_sku), $(wc -l < "$STATE_DIR/acr/_tags.tsv" | tr -d ' ') tags)"
fi

# Tags currently referenced by a container group — the minimum set worth archiving.
python3 - "$STATE_DIR" <<'PY'
import json, os, sys, glob
state = sys.argv[1]
refs = set()
for f in glob.glob(os.path.join(state, "aci", "*.json")):
    d = json.load(open(f))
    for c in d.get("containers", []):
        img = c.get("image", "")
        if "/" in img and ":" in img.rsplit("/", 1)[1]:
            repo, tag = img.rsplit("/", 1)[1].rsplit(":", 1)
            refs.add((repo, tag))
with open(os.path.join(state, "acr", "_deployed_tags.tsv"), "w") as fh:
    for repo, tag in sorted(refs):
        fh.write(f"{repo}\t{tag}\n")
print(f" ok deployed image tags: {len(refs)}")
PY

# --- 3. DNS -------------------------------------------------------------------
if az_ network dns zone show -g "$RESOURCE_GROUP" -n "$DNS_ZONE" >/dev/null 2>&1; then
  az_ network dns zone show -g "$RESOURCE_GROUP" -n "$DNS_ZONE" -o json \
    > "$STATE_DIR/dns/zone.json"
  az_ network dns record-set list -g "$RESOURCE_GROUP" -z "$DNS_ZONE" -o json \
    > "$STATE_DIR/dns/recordsets.json"
  ok "dns  $DNS_ZONE"
fi

# --- 4. Storage ---------------------------------------------------------------
if az_ storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" >/dev/null 2>&1; then
  az_ storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -o json \
    > "$STATE_DIR/storage/account.json"
  az_ storage share-rm list -g "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" -o json \
    > "$STATE_DIR/storage/shares.json"
  ok "storage $STORAGE_ACCOUNT"
fi

# --- 5. Whole-RG ARM export (best-effort; some ACI props are not exportable) ---
az_ group export -n "$RESOURCE_GROUP" --skip-all-params \
  > "$STATE_DIR/resource-group.arm.json" 2>/dev/null \
  && ok "arm  resource-group.arm.json" \
  || warn "full ARM export unavailable (non-fatal — per-resource captures above are authoritative)"

printf '%s\n' "captured_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_DIR/CAPTURED"
log "Done. Restore reads from $STATE_DIR — keep it, it is gitignored."
