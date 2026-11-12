#!/usr/bin/env bash
# 安裝 Project Tracker：
#   1. 放入匯入說明（~/.project-tracker/import-guide.md；已存在就保留你的版本）
#   2. 清除舊版（v0.x）留下的全域 CLAUDE.md 規則、Stop hook 與 ptrack 指令
#   3. 編譯 App、安裝到 ~/Applications 並啟動
# 參數：--no-app 只做 1、2
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PT_HOME="${PTRACK_HOME:-$HOME/.project-tracker}"
CLAUDE_DIR="$HOME/.claude"
WITH_APP=1
for a in "$@"; do
  case "$a" in
    --no-app) WITH_APP=0 ;;
    *) echo "未知參數：$a" >&2; exit 2 ;;
  esac
done

echo "▸ 安裝匯入說明"
mkdir -p "$PT_HOME/templates"
install -m 644 "$ROOT/templates/import-guide.md" "$PT_HOME/templates/import-guide.default.md"
if [[ -f "$PT_HOME/import-guide.md" ]]; then
  echo "  已有匯入說明，保留你的版本（預設版在 templates/import-guide.default.md）"
else
  install -m 644 "$ROOT/templates/import-guide.md" "$PT_HOME/import-guide.md"
fi

echo "▸ 清除舊版設定"
if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]] && grep -q "project-tracker:begin" "$CLAUDE_DIR/CLAUDE.md"; then
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak.$(date +%Y%m%d%H%M%S)"
  TMP="$(mktemp)"
  awk '/<!-- project-tracker:begin -->/{skip=1} !skip{print} /<!-- project-tracker:end -->/{skip=0}' \
    "$CLAUDE_DIR/CLAUDE.md" > "$TMP"
  printf '%s\n' "$(cat "$TMP")" > "$CLAUDE_DIR/CLAUDE.md"
  rm -f "$TMP"
  echo "  已移除 ~/.claude/CLAUDE.md 裡的舊規則（已備份）"
fi
SETTINGS="$CLAUDE_DIR/settings.json"
if [[ -f "$SETTINGS" ]] && grep -q "ptrack hook-stop" "$SETTINGS"; then
  command -v jq >/dev/null || { echo "需要 jq 才能移除舊 hook：brew install jq" >&2; exit 1; }
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  jq '
    if .hooks.Stop then
      .hooks.Stop |= (map(.hooks |= map(select((.command // "") | test("ptrack hook-stop") | not)))
                      | map(select((.hooks | length) > 0)))
      | if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  已移除 settings.json 裡的舊 Stop hook（已備份）"
fi
if [[ -L "$HOME/.local/bin/ptrack" ]]; then rm -f "$HOME/.local/bin/ptrack"; echo "  已移除 ptrack 指令"; fi
if [[ -d "$PT_HOME/bin" ]]; then rm -rf "${PT_HOME:?}/bin"; fi

if [[ $WITH_APP == 1 ]]; then
  "$ROOT/scripts/build-app.sh"
  echo "▸ 安裝到 ~/Applications"
  mkdir -p "$HOME/Applications"
  pkill -x ProjectTracker 2>/dev/null || true
  rm -rf "$HOME/Applications/Project Tracker.app"
  cp -R "$ROOT/build/Project Tracker.app" "$HOME/Applications/"
  open "$HOME/Applications/Project Tracker.app"
fi

echo "✓ 安裝完成。在 App 的「匯入說明」把說明檔丟給 Claude，再把產生的 PROGRESS.md 拖回 App。"
