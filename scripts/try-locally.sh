#!/usr/bin/env bash
# try-locally.sh — run this action's steps on your own machine, the way a
# runner would, without pushing a workflow first.
#
#   bash scripts/try-locally.sh jq tree              packages
#   CASKS="peek" bash scripts/try-locally.sh         casks (macOS)
#   BREWFILE=Brewfile bash scripts/try-locally.sh    a Brewfile
#   POUR_VERSION=0.1.0 PREFIX=/tmp/pour bash scripts/try-locally.sh jq
#
# It reads action.yml, fills in the inputs, honours each step's `if:` and
# runs the steps in order with GITHUB_PATH / GITHUB_ENV / GITHUB_OUTPUT
# wired the same way Actions does. Needs bash, python3 (with PyYAML) and curl.
#
# Copyright (c) 2026 Jagadeesh Kumar S. All rights reserved.
set -euo pipefail
cd "$(dirname "$0")/.."
PACKAGES="${*:-${PACKAGES:-}}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export GITHUB_PATH="$tmp/path" GITHUB_ENV="$tmp/env" GITHUB_OUTPUT="$tmp/output" RUNNER_TEMP="$tmp"
: > "$GITHUB_PATH"; : > "$GITHUB_ENV"; : > "$GITHUB_OUTPUT"
# a runner always has sudo; a root shell in a container may not
if ! command -v sudo >/dev/null && [ "$(id -u)" = 0 ]; then mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexec "$@"\n' > "$tmp/bin/sudo"; chmod +x "$tmp/bin/sudo"; export PATH="$tmp/bin:$PATH"; fi

# a python with PyYAML (a Pour-installed python3 earlier on PATH may lack it)
PY=""; for c in python3 /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import yaml' 2>/dev/null; then PY=$(command -v "$c"); break; fi
done
[ -n "$PY" ] || { echo "need python3 with PyYAML (pip install pyyaml)"; exit 1; }
"$PY" - "$PACKAGES" "${CASKS:-}" "${POUR_VERSION:-latest}" "${PREFIX:-}" "${BREWFILE:-}" "$tmp" <<'PY'
import sys, yaml, json, re
packages, casks, version, prefix, brewfile, tmp = sys.argv[1:7]
inputs = {"packages": packages, "casks": casks, "version": version, "prefix": prefix, "brewfile": brewfile}
a = yaml.safe_load(open("action.yml"))
steps = []
for s in a["runs"]["steps"]:
    cond = s.get("if")
    if cond:
        m = re.fullmatch(r"\s*inputs\.(\w+)\s*!=\s*''\s*", cond)
        if m and not inputs.get(m.group(1)):
            continue
    run = re.sub(r"\$\{\{\s*inputs\.(\w+)\s*\}\}", lambda m: inputs.get(m.group(1), ""), s["run"])
    steps.append({"id": s.get("id", ""), "run": run})
json.dump(steps, open(f"{tmp}/steps.json", "w"))
print(f"{len(steps)} step(s) from action.yml")
PY

n=$("$PY" -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$tmp/steps.json")
for ((i = 0; i < n; i++)); do
  "$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))[int(sys.argv[2])]["run"])' "$tmp/steps.json" "$i" > "$tmp/step.sh"
  id=$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))[int(sys.argv[2])]["id"] or "step "+str(int(sys.argv[2])+1))' "$tmp/steps.json" "$i")
  printf '\033[1;34m▶ %s\033[0m\n' "$id"
  sed 's/^/  │ /' "$tmp/step.sh" | head -3; [ "$(wc -l < "$tmp/step.sh")" -le 3 ] || echo "  │ …"
  # what earlier steps added to PATH and the environment
  while IFS= read -r p; do [ -n "$p" ] && export PATH="$p:$PATH"; done < "$GITHUB_PATH"
  while IFS= read -r kv; do [ -n "$kv" ] && export "$kv"; done < "$GITHUB_ENV"
  bash -e "$tmp/step.sh"
done
printf '\033[1;32m✓ outputs\033[0m\n'; sed 's/^/  /' "$GITHUB_OUTPUT"
