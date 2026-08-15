#!/usr/bin/env bash
# Shared config and helpers for the cost teardown / restore scripts.
# Source this; do not run it directly.

set -euo pipefail

# --- Fixed identifiers for this project (verified live 2026-08-15) -------------
SUBSCRIPTION_ID="ba28a614-4132-4eec-bb77-1345831cb85e"   # "CWM Reporting Application"
RESOURCE_GROUP="CWM_Reporting_App"
LOCATION="eastus2"
ACR_NAME="cwmacr"
STORAGE_ACCOUNT="cwmreportingappsa"
DNS_ZONE="cwm-reporting.opschasingdev.com"

# Parent zone holding the NS delegation for DNS_ZONE. Lives in a different
# subscription, so deleting/recreating the child zone needs a fix-up there.
PARENT_DNS_SUB="7477bc47-19d3-45c2-a0db-168ad85fd44f"    # "Management"
PARENT_DNS_RG="Management"
PARENT_DNS_ZONE="opschasingdev.com"
PARENT_DNS_CHILD="cwm-reporting"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="${STATE_DIR:-$REPO_ROOT/.infra-state}"

# Azure CLI only accepts --subscription AFTER the command group, so this wrapper
# appends it rather than prefixing. `az --subscription X account show` is a parse error.
az_()        { az "$@" --subscription "$SUBSCRIPTION_ID"; }
az_parent_() { az "$@" --subscription "$PARENT_DNS_SUB"; }

# --- Output -------------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m XX\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  local ans
  read -r -p "$1 [type 'yes' to continue]: " ans
  [[ "$ans" == "yes" ]] || die "aborted by user"
}

# --- Preconditions ------------------------------------------------------------
require_az() {
  command -v az >/dev/null 2>&1 || die "azure cli not found on PATH"
  az_ account show >/dev/null 2>&1 \
    || die "not authenticated to subscription $SUBSCRIPTION_ID — run 'az login'"
}

require_state() {
  [[ -d "$STATE_DIR/aci" ]] \
    || die "no captured state at $STATE_DIR — run scripts/cost/capture-state.sh first"
}

# --- Azure lookups ------------------------------------------------------------
aci_groups() {
  az_ container list -g "$RESOURCE_GROUP" --query "[].name" -o tsv
}

aci_state() {
  az_ container show -g "$RESOURCE_GROUP" -n "$1" \
    --query "instanceView.state" -o tsv 2>/dev/null || echo "Absent"
}

acr_sku() {
  az_ acr show -n "$ACR_NAME" --query "sku.name" -o tsv 2>/dev/null || echo "Absent"
}

acr_login_server() {
  az_ acr show -n "$ACR_NAME" --query "loginServer" -o tsv
}

acr_password() {
  az_ acr credential show -n "$ACR_NAME" --query "passwords[0].value" -o tsv
}

storage_key() {
  az_ storage account keys list -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" \
    --query "[0].value" -o tsv
}
