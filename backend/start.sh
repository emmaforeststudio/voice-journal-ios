#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

CODEX_RUNTIME_NODE="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"

if command -v node >/dev/null 2>&1; then
  NODE_BIN=$(command -v node)
elif [ -x "$CODEX_RUNTIME_NODE" ]; then
  NODE_BIN=$CODEX_RUNTIME_NODE
elif [ -x /Applications/Codex.app/Contents/Resources/node ]; then
  NODE_BIN=/Applications/Codex.app/Contents/Resources/node
else
  echo "Node.js was not found. Install Node.js or run this backend from Codex." >&2
  exit 1
fi

exec "$NODE_BIN" "$SCRIPT_DIR/server.mjs"
