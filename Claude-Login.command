#!/bin/bash
# Opens the official Claude Code login for the CLI bundled with the workbench (or $EVA_CLAUDE).
ROOT="$(cd "$(dirname "$0")" && pwd)" || exit 1
ARCH="$(uname -m)"; [ "$ARCH" = "x86_64" ] && ARCH="x64"
CLAUDE="${EVA_CLAUDE:-$ROOT/workbench/node_modules/@anthropic-ai/claude-agent-sdk-darwin-$ARCH/claude}"
if [ ! -x "$CLAUDE" ]; then CLAUDE="$(command -v claude)"; fi
if [ -z "$CLAUDE" ]; then echo "找不到 Claude Code CLI。请先在 workbench 目录运行 npm install，或设置 EVA_CLAUDE。"; read -r -p '按 Return 关闭。'; exit 1; fi
"$CLAUDE" auth login
status=$?
printf '\n登录完成后回到 EVA，点击“刷新”。\n'
read -r -p '按 Return 关闭。'
exit "$status"
