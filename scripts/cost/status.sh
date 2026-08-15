#!/usr/bin/env bash
# Show what is currently costing money, and the month-to-date spend by resource.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_az

log "Container groups"
printf '     %-22s %s\n' "NAME" "STATE"
for g in $(aci_groups); do
  s="$(aci_state "$g")"
  if [[ "$s" == "Running" ]]; then
    printf '     \033[1;31m%-22s %s  <-- billing\033[0m\n' "$g" "$s"
  else
    printf '     %-22s %s\n' "$g" "$s"
  fi
done

log "Container registry"
sku="$(acr_sku)"
if [[ "$sku" == "Absent" ]]; then
  printf '     %s: deleted\n' "$ACR_NAME"
else
  bytes="$(az_ acr show-usage -n "$ACR_NAME" \
            --query "value[?name=='Size'].currentValue | [0]" -o tsv)"
  printf '     %s: %s sku, %s MB used  (Basic ~$5/mo, Standard ~$20/mo)\n' \
    "$ACR_NAME" "$sku" "$(( bytes / 1048576 ))"
fi

log "DNS + storage"
az_ network dns zone show -g "$RESOURCE_GROUP" -n "$DNS_ZONE" >/dev/null 2>&1 \
  && printf '     %s: present (~$0.50/mo)\n' "$DNS_ZONE" \
  || printf '     %s: deleted\n' "$DNS_ZONE"
az_ storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" >/dev/null 2>&1 \
  && printf '     %s: present (~$0.01/mo at current usage)\n' "$STORAGE_ACCOUNT" \
  || printf '     %s: deleted\n' "$STORAGE_ACCOUNT"

log "Month-to-date cost by resource"
body='{"type":"ActualCost","timeframe":"MonthToDate","dataset":{"granularity":"None",
"aggregation":{"totalCost":{"name":"Cost","function":"Sum"}},
"grouping":[{"type":"Dimension","name":"ServiceName"},{"type":"Dimension","name":"ResourceId"}]}}'
if az rest --method post \
     --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/query?api-version=2023-03-01" \
     --body "$body" -o json > /tmp/cwm-cost.json 2>/dev/null; then
  python3 - <<'PY'
import json
d = json.load(open("/tmp/cwm-cost.json"))
rows = d["properties"]["rows"]
for r in sorted(rows, key=lambda x: -x[0]):
    rid = r[2].split("/")[-1] if len(r) > 2 and r[2] else ""
    print(f"     {r[0]:8.3f}  {r[1]:<22} {rid}")
print(f"     {sum(r[0] for r in rows):8.2f}  TOTAL")
PY
  rm -f /tmp/cwm-cost.json
else
  warn "cost query failed (Cost Management throttles aggressively — retry in a minute)"
fi
