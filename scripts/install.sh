#!/usr/bin/env bash
# 安裝 project-tracker：
#   1. 複製 ptrack 到 ~/.project-tracker/bin，並在 ~/.local/bin 建立連結
#   2. 把進度追蹤規則加進 ~/.claude/CLAUDE.md（以標記區塊包住，可重複執行）
#   3. 在 ~/.claude/settings.json 註冊 Stop hook（先備份）
#   4. 編譯選單列 App 並安裝到 ~/Applications，然後啟動
# 參數：--no-app 只裝 CLI／規則／hook；--no-hook 不改 settings.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PT_HOME="${PTRACK_HOME:-$HOME/.project-tracker}"
CLAUDE_DIR="$HOME/.claude"
WITH_APP=1; WITH_HOOK=1
for a in "$@"; do
  case "$a" in
    --no-app) WITH_APP=0 ;;
    --no-hook) WITH_HOOK=0 ;;
    *) echo "未知參數：$a" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "需要 jq：brew install jq" >&2; exit 1; }

echo "▸ 安裝 ptrack CLI"
mkdir -p "$PT_HOME/bin" "$PT_HOME/projects" "$HOME/.local/bin"
install -m 755 "$ROOT/bin/ptrack" "$PT_HOME/bin/ptrack"
ln -sf "$PT_HOME/bin/ptrack" "$HOME/.local/bin/ptrack"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "  ⚠ ~/.local/bin 不在 PATH，規則中會改用絕對路徑" ;; esac

echo "▸ 更新 ~/.claude/CLAUDE.md"
mkdir -p "$CLAUDE_DIR"
touch "$CLAUDE_DIR/CLAUDE.md"
SNIPPET="$ROOT/templates/claude-md-snippet.md"
TMP="$(mktemp)"
# 移除舊的標記區塊後重新附加，確保重複安裝不會重複規則
awk '/<!-- project-tracker:begin -->/{skip=1} !skip{print} /<!-- project-tracker:end -->/{skip=0}' \
  "$CLAUDE_DIR/CLAUDE.md" > "$TMP"
# 去掉檔尾多餘空行
printf '%s\n' "$(cat "$TMP")" > "$TMP.2"
{ cat "$TMP.2"; echo; cat "$SNIPPET"; } > "$CLAUDE_DIR/CLAUDE.md"
rm -f "$TMP" "$TMP.2"

if [[ $WITH_HOOK == 1 ]]; then
  echo "▸ 註冊 Claude Code Stop hook"
  SETTINGS="$CLAUDE_DIR/settings.json"
  [[ -s "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  HOOK_CMD="$PT_HOME/bin/ptrack hook-stop"
  jq --arg cmd "$HOOK_CMD" '
    .hooks //= {} | .hooks.Stop //= [] |
    # 先移除舊的 ptrack hook，再加入新的
    .hooks.Stop |= (map(.hooks |= map(select((.command // "") | test("ptrack hook-stop") | not)))
                    | map(select((.hooks | length) > 0))) |
    .hooks.Stop += [{"hooks": [{"type": "command", "command": $cmd, "timeout": 15}]}]
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
fi

if [[ $WITH_APP == 1 ]]; then
  "$ROOT/scripts/build-app.sh"
  echo "▸ 安裝到 ~/Applications"
  mkdir -p "$HOME/Applications"
  pkill -x ProjectTracker 2>/dev/null || true
  rm -rf "$HOME/Applications/Project Tracker.app"
  cp -R "$ROOT/build/Project Tracker.app" "$HOME/Applications/"
  open "$HOME/Applications/Project Tracker.app"
fi

echo "✓ 安裝完成。下次 Claude Code session 收工時就會自動寫入進度。"
