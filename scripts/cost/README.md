# Cost teardown / restore

Deterministic scripts to park this project's Azure footprint and bring it back.
State observed live on 2026-08-15; subscription `CWM Reporting Application`
(`ba28a614-4132-4eec-bb77-1345831cb85e`), resource group `CWM_Reporting_App`.

## Run rate at time of writing

| Item | July actual | Aug 1–15 actual | Notes |
|---|---:|---:|---|
| Container Instances | $20.70 | $16.18 | all from `cwm-staging-web`, the one group left running |
| Container Registry | $20.66 | $9.56 | Standard SKU, flat rate, 877 MB stored |
| Azure DNS | $0.50 | $0.23 | one zone |
| Storage | $0.01 | $0.005 | ~1 GB across 5 file shares |
| **Total** | **$41.88** | **$25.97** | ≈ **$52/mo** run rate |

15 of 16 container groups are already `Stopped`. Stopped ACI bills $0, so the
remaining spend is one running web container plus the registry SKU.

## Tiers

| Tier | Action | Saves/mo | Reversible | Data loss |
|---|---|---:|---|---|
| 1 | Stop running container groups | ~$32–40 | seconds | none |
| 2 | ACR Standard → Basic | ~$15 | seconds | none |
| 3 | Delete container groups | $0 | minutes | none (state captured) |
| 4 | Archive images, delete registry | ~$5 | ~20 min | none (tarballs) |
| 5 | Delete DNS zone | ~$0.50 | minutes + DNS propagation | none |
| 6 | Delete the resource group | ~$0.01 | ~30 min | share contents unless archived |

**Tiers 1 + 2 recover about 89% of the spend in two commands with zero data loss.**
Tier 3 saves nothing — it is cleanup, not cost. It is worth doing anyway because
the CWM API keys currently sit in plaintext ACI environment variables.

## Usage

```bash
./status.sh                 # what is billing right now + month-to-date cost
./capture-state.sh          # ALWAYS run before any destructive tier
python3 scrub-secrets.py    # strip credentials out of the capture
./down.sh 1 2               # the recommended stop point
./up.sh 2 1                 # undo it
```

Restore runs in **descending** tier order — the registry must exist before
container groups can pull from it:

```bash
./up.sh 6 5 4 3 1           # full rebuild from nothing
```

`ASSUME_YES=1` skips confirmation prompts. `START_ALL=1 ./up.sh 1` starts every
group rather than only those that were running at capture time.

## Things that will bite you

- **ACI public IPs are not stable.** Stopping a container group releases its IP;
  starting assigns a new one. `up.sh` re-points the DNS A record automatically
  (`@` for prod-web, `staging` for staging-web) — this is the same fix-up the
  GitHub deploy workflow does.
- **A recreated ACR gets a new login server.** The current one is
  `cwmacr-cbd0gjgfbehxbffb.azurecr.io`; the random suffix is not reproducible.
  After `up.sh 4`, update the `ACR_LOGIN_SERVER` GitHub secret.
- **A recreated DNS zone gets new nameservers.** The delegation for
  `cwm-reporting` lives in the `opschasingdev.com` zone in the **Management**
  subscription (`7477bc47-…`). `up.sh 5` rewrites that NS record for you.
- **`.infra-state/` has been scrubbed.** ACI stored the CWM keys as plain (not
  secure) environment variables, so `capture-state.sh` writes them to disk in
  plaintext. `scrub-secrets.py` has since replaced `CWM_PrivateKey`,
  `CWM_PublicKey`, `CWM_ClientID` and `AZURE_CREDENTIALS_B64` with
  `__REDACTED__` across all 16 captures **and** `resource-group.arm.json`
  (which carried 44 more copies). Re-run it after any fresh `capture-state.sh`:

  ```bash
  ./capture-state.sh && python3 scrub-secrets.py
  ```

  Restoring a scrubbed capture needs the values back:

  ```bash
  ./up.sh 3     # fails loudly, naming the missing credentials
  ```

  Supply them per-group with `render-aci-yaml.py --secret NAME=VALUE`, or just
  redeploy from source — the GitHub Actions workflows still hold every secret.
  Note the keys were **not rotated**, so they remain valid in ConnectWise and in
  GitHub Actions secrets; scrubbing removed the local copy, nothing more.
- **`az container export` is not used here.** It strips both secrets and emits a
  preview API schema. `render-aci-yaml.py` rebuilds the exact `2021-09-01` shape
  the workflows use and re-injects the ACR password and storage key from live
  Azure at restore time.

## Verified vs. unverified

Verified live: `capture-state.sh`, `status.sh`, and that `render-aci-yaml.py`
emits YAML matching the deploy workflows field-for-field (same `apiVersion`,
same key names, secrets injected).

Not yet exercised against Azure: the destructive tiers and their restores. The
first real `up.sh 3` is the round-trip proof; run it on a single staging group
before trusting it broadly.

## Alternative restore path

The GitHub Actions workflows in `.github/workflows/` are the original source of
truth and already inject every secret. Adding `workflow_dispatch:` to each `on:`
block makes "redeploy everything from source" a one-click operation and removes
any dependence on `.infra-state/`. Recommended regardless.
