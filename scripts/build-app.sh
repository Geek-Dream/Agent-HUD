#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/AgentHUD.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

cp "$ROOT_DIR/.build/release/AgentHUD" "$CONTENTS_DIR/MacOS/AgentHUD"
cp "$ROOT_DIR/packaging/Info.plist" "$CONTENTS_DIR/Info.plist"

chmod +x "$CONTENTS_DIR/MacOS/AgentHUD"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
