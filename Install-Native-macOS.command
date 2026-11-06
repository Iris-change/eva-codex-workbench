#!/bin/bash
# Builds the native EVA Workbench.app and installs the local service it starts.
# Existing conversations in ~/Library/Application Support/EVA-Workbench/workbench/data are never touched.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
ROOT="$(cd "$(dirname "$0")" && pwd)" || exit 1
SUPPORT="$HOME/Library/Application Support/EVA-Workbench"
fail() { printf '%s\n' "$1"; read -r -p '按 Return 关闭。'; exit 1; }
[ "$(uname -s)" = "Darwin" ] || fail "仅支持 macOS。"
command -v npm >/dev/null 2>&1 || fail "需要 Node.js 20+（含 npm）。"
[ -x /opt/homebrew/bin/node ] || [ -x /usr/local/bin/node ] || fail "应用会在 /opt/homebrew/bin 或 /usr/local/bin 查找 node，请用 Homebrew 或官方安装包安装 Node.js。"
command -v swiftc >/dev/null 2>&1 || fail "需要 Xcode 或 Apple 命令行工具：xcode-select --install"
if pgrep -f "EVA Workbench.app/Contents/MacOS/eva-workbench" >/dev/null; then fail "请先退出正在运行的 EVA Workbench。"; fi
set -e
mkdir -p "$SUPPORT/workbench"
rsync -a --exclude data/ --exclude node_modules/ --exclude tests/ --exclude .verification/ "$ROOT/workbench/" "$SUPPORT/workbench/"
cp "$ROOT/Claude-Login.command" "$SUPPORT/Claude-Login.command"; chmod +x "$SUPPORT/Claude-Login.command"
(cd "$SUPPORT/workbench" && npm ci --omit=dev)
python3 -I "$ROOT/native-macos/build-app.py" "$ROOT/build-native"
mkdir -p "$HOME/Applications"
if [ -d "$HOME/Applications/EVA Workbench.app" ]; then rm -rf "$HOME/Applications/EVA Workbench.app.previous"; mv "$HOME/Applications/EVA Workbench.app" "$HOME/Applications/EVA Workbench.app.previous"; fi
ditto "$ROOT/build-native/EVA Workbench.app" "$HOME/Applications/EVA Workbench.app"
printf '\n已安装到 ~/Applications/EVA Workbench.app。首次使用 Claude Code 请在应用里点“登录”，或运行 Claude-Login.command。\n'
read -r -p '按 Return 关闭。'
