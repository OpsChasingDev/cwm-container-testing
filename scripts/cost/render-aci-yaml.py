#!/usr/bin/env python3
"""Turn a captured container-group JSON into a deployable `az container create --file` YAML.

`az container export` strips secrets AND emits a preview API schema. This renderer
instead builds the exact 2021-09-01 shape the GitHub workflows use, and re-injects
the two secrets Azure never returns (ACR password, storage account key) from
arguments supplied at restore time.

If the capture has been through scrub-secrets.py, credential values read
__REDACTED__. Supply them again with --secret NAME=VALUE (repeatable); rendering
fails rather than emitting a deployment that would run with a literal
"__REDACTED__" credential.

Usage:
  render-aci-yaml.py <captured.json> --acr-password PW --storage-key KEY \
      [--secret CWM_PrivateKey=...] > deploy.yaml
"""
import argparse
import json
import sys

REDACTED = "__REDACTED__"


def q(v):
    """YAML-quote a scalar so multi-line / special-char values survive."""
    return json.dumps(v if isinstance(v, str) else str(v))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("captured")
    ap.add_argument("--acr-password", required=True)
    ap.add_argument("--storage-key", required=True)
    ap.add_argument("--secret", action="append", default=[],
                    metavar="NAME=VALUE",
                    help="re-supply a scrubbed credential; repeatable")
    args = ap.parse_args()

    supplied = {}
    for pair in args.secret:
        if "=" not in pair:
            sys.exit(f"--secret expects NAME=VALUE, got {pair!r}")
        k, v = pair.split("=", 1)
        supplied[k] = v

    d = json.load(open(args.captured))

    # Re-inject scrubbed credentials, and refuse to render if any remain.
    missing = []
    for c in d["containers"]:
        for e in c.get("environmentVariables") or []:
            for field in ("value", "secureValue"):
                if e.get(field) == REDACTED:
                    if e["name"] in supplied:
                        e[field] = supplied[e["name"]]
                    else:
                        missing.append(e["name"])
    if missing:
        sys.exit(
            f"{args.captured}: capture was scrubbed; these credentials must be "
            f"re-supplied with --secret NAME=VALUE: {', '.join(sorted(set(missing)))}\n"
            f"They are still present as GitHub Actions secrets — or redeploy from "
            f"source via .github/workflows/ instead."
        )
    out = []
    w = out.append

    w("apiVersion: '2021-09-01'")
    w(f"location: {d['location']}")
    w(f"name: {d['name']}")
    w("properties:")

    # --- volumes ---
    vols = d.get("volumes") or []
    if vols:
        w("  volumes:")
        for v in vols:
            w(f"  - name: {v['name']}")
            af = v.get("azureFile") or {}
            w("    azureFile:")
            w(f"      shareName: {af['shareName']}")
            w(f"      storageAccountName: {af['storageAccountName']}")
            w(f"      storageAccountKey: {q(args.storage_key)}")

    # --- containers ---
    w("  containers:")
    for c in d["containers"]:
        w(f"  - name: {c['name']}")
        w("    properties:")
        w(f"      image: {c['image']}")
        req = c["resources"]["requests"]
        w("      resources:")
        w("        requests:")
        w(f"          cpu: {req['cpu']}")
        w(f"          memoryInGb: {req.get('memoryInGb', req.get('memoryInGB'))}")
        if c.get("ports"):
            w("      ports:")
            for p in c["ports"]:
                w(f"      - port: {p['port']}")
                w(f"        protocol: {p.get('protocol', 'TCP')}")
        if c.get("environmentVariables"):
            w("      environmentVariables:")
            for e in c["environmentVariables"]:
                w(f"        - name: {e['name']}")
                if e.get("secureValue") is not None:
                    w(f"          secureValue: {q(e['secureValue'])}")
                else:
                    w(f"          value: {q(e.get('value', ''))}")
        if c.get("volumeMounts"):
            w("      volumeMounts:")
            for m in c["volumeMounts"]:
                w(f"        - name: {m['name']}")
                w(f"          mountPath: {m['mountPath']}")

    w(f"  osType: {d.get('osType', 'Linux')}")

    # --- registry credentials ---
    for cred in d.get("imageRegistryCredentials") or []:
        w("  imageRegistryCredentials:")
        w(f"  - server: {cred['server']}")
        w(f"    username: {cred['username']}")
        w(f"    password: {q(args.acr_password)}")
        break

    w(f"  restartPolicy: {d.get('restartPolicy', 'Always')}")

    # --- public IP (web only) ---
    ipa = d.get("ipAddress") or {}
    if ipa.get("type") == "Public":
        w("  ipAddress:")
        w("    type: Public")
        if ipa.get("ports"):
            w("    ports:")
            for p in ipa["ports"]:
                w(f"    - protocol: {p.get('protocol', 'TCP')}")
                w(f"      port: {p['port']}")

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
