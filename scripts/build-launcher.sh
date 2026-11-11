#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/packaging/AgentHUDLauncher"
APP_DIR="$ROOT_DIR/AgentHUD Launcher.app"
CONTENTS_DIR="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS"

cp "$SOURCE_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$SOURCE_DIR/AgentHUDLauncher.zsh" "$CONTENTS_DIR/MacOS/AgentHUDLauncher"
chmod +x "$CONTENTS_DIR/MacOS/AgentHUDLauncher"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
