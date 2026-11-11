#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER_PATH="$("$ROOT_DIR/scripts/build-launcher.sh")"
DESKTOP_LINK="$HOME/Desktop/启动 AgentHUD.app"

if [[ -e "$DESKTOP_LINK" && ! -L "$DESKTOP_LINK" ]]; then
    echo "Refusing to replace existing item: $DESKTOP_LINK" >&2
    exit 1
fi

ln -sfn "$LAUNCHER_PATH" "$DESKTOP_LINK"
echo "$DESKTOP_LINK"
