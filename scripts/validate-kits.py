#!/usr/bin/env python3
"""Validate every kit.json in this repository against schemas/kit.schema.json.

Usage:
    python3 scripts/validate-kits.py

Requires the `jsonschema` package. If it isn't installed:
    python3 -m venv .venv && .venv/bin/pip install jsonschema
    .venv/bin/python scripts/validate-kits.py
"""

import glob
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    try:
        from jsonschema import Draft7Validator
    except ImportError:
        print(
            "error: the 'jsonschema' package is required.\n"
            "  python3 -m venv .venv && .venv/bin/pip install jsonschema\n"
            "  .venv/bin/python scripts/validate-kits.py",
            file=sys.stderr,
        )
        return 2

    schema_path = os.path.join(REPO_ROOT, "schemas", "kit.schema.json")
    with open(schema_path, encoding="utf-8") as fh:
        validator = Draft7Validator(json.load(fh))

    manifests = sorted(glob.glob(os.path.join(REPO_ROOT, "*", "kit.json")))
    if not manifests:
        print("error: no kit.json files found", file=sys.stderr)
        return 2

    failures = 0
    for path in manifests:
        name = os.path.basename(os.path.dirname(path))
        with open(path, encoding="utf-8") as fh:
            try:
                manifest = json.load(fh)
            except json.JSONDecodeError as exc:
                print(f"FAIL {name}: invalid JSON — {exc}")
                failures += 1
                continue

        errors = sorted(validator.iter_errors(manifest), key=lambda e: list(e.path))
        if errors:
            failures += 1
            print(f"FAIL {name}")
            for err in errors:
                location = "/".join(str(p) for p in err.path) or "(root)"
                print(f"       {location}: {err.message}")
        else:
            print(f"OK   {name}")

    total = len(manifests)
    print(f"\n{total - failures}/{total} manifests valid")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
