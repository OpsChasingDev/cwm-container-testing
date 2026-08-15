#!/usr/bin/env bash
# Pull every Azure File share down to .infra-state/storage/shares/ before a
# tier-6 teardown, and push them back afterwards.
#
#   ./archive-shares.sh download
#   ./archive-shares.sh upload

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_az
command -v azcopy >/dev/null 2>&1 || AZCOPY_MISSING=1

MODE="${1:-download}"
DEST="$STATE_DIR/storage/shares"
mkdir -p "$DEST"

KEY="$(storage_key)"
SHARES=$(az_ storage share-rm list -g "$RESOURCE_GROUP" \
          --storage-account "$STORAGE_ACCOUNT" --query "[].name" -o tsv)

case "$MODE" in
  download)
    log "Downloading shares to $DEST"
    for s in $SHARES; do
      mkdir -p "$DEST/$s"
      az storage file download-batch \
        --account-name "$STORAGE_ACCOUNT" --account-key "$KEY" \
        --source "$s" --destination "$DEST/$s" --no-progress >/dev/null
      ok "downloaded $s ($(du -sh "$DEST/$s" | cut -f1))"
    done
    ;;
  upload)
    log "Uploading shares from $DEST"
    for s in $SHARES; do
      [[ -d "$DEST/$s" ]] || { warn "no local copy of $s"; continue; }
      az storage file upload-batch \
        --account-name "$STORAGE_ACCOUNT" --account-key "$KEY" \
        --destination "$s" --source "$DEST/$s" --no-progress >/dev/null
      ok "uploaded $s"
    done
    ;;
  *) die "usage: archive-shares.sh [download|upload]" ;;
esac

[[ -n "${AZCOPY_MISSING:-}" ]] && warn "azcopy not installed; used the slower CLI batch transfer"
exit 0
