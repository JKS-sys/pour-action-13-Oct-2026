#!/usr/bin/env bash
# pour-action · ci.sh — the action's steps with colour and pictures in the log:
# a gold banner with a filling glass, one collapsible group per step, every package
# timed, and a job summary with a table, bars and a chart of where the time went.
# GitHub's log renders ANSI colour (Pour's own output is coloured there too: it turns
# colour on when GITHUB_ACTIONS is set). No pink anywhere. CI has no speakers, so the
# sounds Pour plays on a desktop stay off here.
#
#   bash scripts/ci.sh setup | install "jq ffmpeg" | cask "peek" | bundle Brewfile | summary
#
# Copyright (c) 2026 Jagadeesh Kumar S. All rights reserved.
set -euo pipefail

E=$'\033'
gold="${E}[1;38;2;232;181;58m"; teal="${E}[1;38;2;45;212;191m"; sky="${E}[38;2;56;189;248m"
lime="${E}[38;2;163;230;53m"; cyan="${E}[38;2;34;211;238m"; amber="${E}[38;2;245;158;11m"
violet="${E}[38;2;167;139;250m"; slate="${E}[38;2;148;163;184m"; red="${E}[1;38;2;248;113;113m"; off="${E}[0m"
STATE="${RUNNER_TEMP:-/tmp}/pour-action.tsv"

group() { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }
now_ms() { python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || echo $(( $(date +%s) * 1000 )); }

banner() {
  local glass=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█") c=("$gold" "$cyan" "$lime" "$violet" "$amber" "$sky" "$teal" "$gold") line="" i
  for i in 0 1 2 3 4 5 6 7; do line+="${c[$i]}${glass[$i]}${off}"; done
  printf '%s\n' "${gold}  ╭──────────────────────────────────────────╮${off}"
  printf '%s\n' "${gold}  │${off}  🍶 ${gold}Pour${off} ${slate}·${off} ${teal}packages in milliseconds${off}     ${gold}│${off}"
  printf '%s\n' "${gold}  │${off}  ${line} ${slate}by Jagadeesh Kumar S${off}         ${gold}│${off}"
  printf '%s\n' "${gold}  ╰──────────────────────────────────────────╯${off}"
}

record() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$STATE"; }   # kind name ms status

timed() { # timed KIND NAME -- command…
  local kind=$1 name=$2; shift 3
  local t0 t1 st=ok
  t0=$(now_ms)
  if "$@"; then :; else st=failed; fi
  t1=$(now_ms)
  record "$kind" "$name" $((t1 - t0)) "$st"
  if [ "$st" = ok ]; then
    printf '  %s✓%s %s%s%s %spoured in %s ms%s\n' "$lime" "$off" "$teal" "$name" "$off" "$slate" $((t1 - t0)) "$off"
  else
    printf '  %s✗ %s failed%s\n' "$red" "$name" "$off"; echo "::error title=Pour::$kind $name failed"; return 1
  fi
}

case "${1:-}" in
  setup)
    : > "$STATE"
    banner
    group "🍶 Setting up Pour"
    os=$(uname -s); arch=$(uname -m)
    case "$os" in Darwin) os=macos;; Linux) os=linux;; MINGW*|MSYS*|CYGWIN*) os=windows;; FreeBSD) os=freebsd;; *) echo "::error::Pour has no build for $os"; exit 1;; esac
    case "$arch" in arm64|aarch64) arch=arm64;; x86_64|amd64) arch=x86_64;; esac
    asset="pour-$os-$arch"; exe=pour; [ "$os" = windows ] && { asset="$asset.exe"; exe=pour.exe; }
    ver="${INPUT_VERSION:-latest}"
    if [ "$ver" = latest ]; then url="https://ipconfig.co.network/pour/dl/$asset"; alt="https://github.com/JKS-sys/pour-13-Oct-2026/releases/latest/download/$asset"
    else url="https://ipconfig.co.network/pour/dl/v$ver/$asset"; alt="https://github.com/JKS-sys/pour-13-Oct-2026/releases/download/v$ver/$asset"; fi
    prefix="${INPUT_PREFIX:-}"
    if [ -z "$prefix" ]; then if [ "$os" = windows ]; then prefix="$RUNNER_TEMP/pour"; else prefix=/opt/pour; fi; fi
    if [ "$os" != windows ] && ! mkdir -p "$prefix" 2>/dev/null; then sudo mkdir -p "$prefix" && sudo chown -R "$(id -un)" "$prefix"; fi
    mkdir -p "$prefix/bin"
    printf '  %s↓%s %s%s%s\n' "$sky" "$off" "$cyan" "$asset" "$off"
    t0=$(now_ms)
    curl -fsL --retry 3 -o "$prefix/bin/$exe" "$url" || curl -fsSL --retry 3 -o "$prefix/bin/$exe" "$alt"
    chmod +x "$prefix/bin/$exe"
    { echo "$prefix/bin"; } >> "$GITHUB_PATH"
    { echo "POUR_PREFIX=$prefix"; echo "FORCE_COLOR=1"; } >> "$GITHUB_ENV"
    export POUR_PREFIX="$prefix" FORCE_COLOR=1
    "$prefix/bin/$exe" update
    record setup "pour $("$prefix/bin/$exe" --version | awk '{print $2}')" $(( $(now_ms) - t0 )) ok
    echo "prefix=$prefix" >> "$GITHUB_OUTPUT"
    echo "version=$("$prefix/bin/$exe" --version | awk '{print $2}')" >> "$GITHUB_OUTPUT"
    endgroup ;;
  install|cask)
    kind=$1; list=${2:-}
    [ -n "$list" ] || exit 0
    group "📦 pour install ${kind/cask/--cask }$list"
    flag=(); [ "$kind" = cask ] && flag=(--cask)
    for p in $list; do timed "$kind" "$p" -- pour install "${flag[@]}" "$p"; done
    endgroup ;;
  bundle)
    group "📋 pour bundle install --file $2"
    timed bundle "$2" -- pour bundle install --file "$2"
    endgroup ;;
  summary)
    [ -s "$STATE" ] || exit 0
    [ -n "${GITHUB_STEP_SUMMARY:-}" ] || GITHUB_STEP_SUMMARY=/dev/stdout
    total=$(awk -F'\t' '{s+=$3} END {print s+0}' "$STATE")
    max=$(awk -F'\t' '$3>m{m=$3} END {print m+1}' "$STATE")
    {
      echo "## 🍶 Pour poured $(awk -F'\t' '$1!="setup"' "$STATE" | wc -l | tr -d ' ') package(s) in ${total} ms"
      echo
      echo "| | Package | Kind | Time | |"
      echo "|---|---|---|---:|---|"
      awk -F'\t' -v max="$max" '{
        n = int(($3 / max) * 20 + 0.5); bar = ""; for (i = 0; i < n; i++) bar = bar "█"; for (; i < 20; i++) bar = bar "░";
        icon = ($4 == "ok") ? "✅" : "❌"; kind = ($1 == "cask") ? "app (--cask)" : ($1 == "install") ? "formula / tool" : $1;
        printf "| %s | `%s` | %s | %d ms | `%s` |\n", icon, $2, kind, $3, bar }' "$STATE"
      echo
      echo '```mermaid'
      echo 'pie showData title Where the time went (ms)'
      awk -F'\t' '{ printf "  \"%s\" : %d\n", $2, ($3 > 0 ? $3 : 1) }' "$STATE"
      echo '```'
      echo
      echo "<sub>Pour by Jagadeesh Kumar S · <a href=\"https://ipconfig.co.network/pour\">ipconfig.co.network/pour</a> · ⭐ <a href=\"https://github.com/JKS-sys/pour-13-Oct-2026\">star the repository</a></sub>"
    } >> "$GITHUB_STEP_SUMMARY"
    printf '%s🥂 done%s %sin %s ms%s\n' "$gold" "$off" "$slate" "$total" "$off" ;;
  *) echo "usage: ci.sh setup | install LIST | cask LIST | bundle FILE | summary"; exit 2 ;;
esac
