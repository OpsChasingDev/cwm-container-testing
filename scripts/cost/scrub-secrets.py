#!/usr/bin/env python3
"""Redact credential values from the captured state in .infra-state/.

`az container show` returns ACI environment variables in plaintext because this
project stored them as plain (not secure) variables. capture-state.sh therefore
writes live credentials to disk. This tool replaces those values with a sentinel
so the capture keeps its structure — image, CPU, mounts, volumes, non-secret
config — without carrying the secrets.

Azure already strips `storageAccountKey` and the registry `password` (they come
back null), so environment variables are the only exposure.

Restoring a scrubbed capture requires re-supplying the values; render-aci-yaml.py
refuses to emit a deployment containing the sentinel.

Usage:
  scrub-secrets.py [--state DIR] [--dry-run]
"""
import argparse
import glob
import json
import os
import sys

REDACTED = "__REDACTED__"

# Environment variables whose values are credentials.
SECRET_NAMES = {
    "CWM_PrivateKey",
    "CWM_PublicKey",
    "CWM_ClientID",
    "AZURE_CREDENTIALS_B64",
}


def scrub(node, hits):
    """Walk arbitrary JSON; redact {name: <secret>, value/secureValue: ...} pairs."""
    if isinstance(node, dict):
        name = node.get("name")
        if isinstance(name, str) and name in SECRET_NAMES:
            for field in ("value", "secureValue"):
                if field in node and node[field] not in (None, REDACTED):
                    node[field] = REDACTED
                    hits.append(name)
        for v in node.values():
            scrub(v, hits)
    elif isinstance(node, list):
        for v in node:
            scrub(v, hits)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", ".infra-state"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    state = os.path.abspath(args.state)
    if not os.path.isdir(state):
        sys.exit(f"no capture directory at {state}")

    targets = sorted(glob.glob(os.path.join(state, "aci", "*.json")))
    arm = os.path.join(state, "resource-group.arm.json")
    if os.path.exists(arm):
        targets.append(arm)

    total = 0
    for path in targets:
        with open(path) as fh:
            doc = json.load(fh)
        hits = []
        scrub(doc, hits)
        rel = os.path.relpath(path, state)
        if hits:
            total += len(hits)
            if not args.dry_run:
                with open(path, "w") as fh:
                    json.dump(doc, fh, indent=2)
                    fh.write("\n")
            counts = ", ".join(f"{n}x{hits.count(n)}" if hits.count(n) > 1 else n
                               for n in sorted(set(hits)))
            print(f"  {'would scrub' if args.dry_run else 'scrubbed'}  {rel}  ({counts})")
        else:
            print(f"  clean        {rel}")

    print(f"\n{'would redact' if args.dry_run else 'redacted'} {total} value(s) "
          f"across {len(targets)} file(s)")
    if not args.dry_run and total:
        marker = os.path.join(state, "SCRUBBED")
        with open(marker, "w") as fh:
            fh.write("Credential env values replaced with %s.\n" % REDACTED)
            fh.write("Names redacted: %s\n" % ", ".join(sorted(SECRET_NAMES)))
            fh.write("Restore requires re-supplying these via "
                     "render-aci-yaml.py --secret NAME=VALUE\n")


if __name__ == "__main__":
    main()
