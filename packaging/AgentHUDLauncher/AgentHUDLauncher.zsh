#!/bin/zsh

set -u

SELF="${0:A}"
MACOS_DIR="${SELF:h}"
CONTENTS_DIR="${MACOS_DIR:h}"
BUNDLE_DIR="${CONTENTS_DIR:h}"
ROOT_DIR="${BUNDLE_DIR:h}"
APP_PATH="$ROOT_DIR/build/AgentHUD.app"
LOG_DIR="$HOME/Library/Logs/AgentHUD"
LOG_PATH="$LOG_DIR/launcher.log"

mkdir -p "$LOG_DIR"

needs_build=0
if [[ ! -x "$APP_PATH/Contents/MacOS/AgentHUD" ]]; then
    needs_build=1
elif [[ -n "$(find \
    "$ROOT_DIR/Sources" \
    "$ROOT_DIR/Package.swift" \
    "$ROOT_DIR/packaging/Info.plist" \
    -newer "$APP_PATH/Contents/MacOS/AgentHUD" \
    -print -quit 2>/dev/null)" ]]; then
    needs_build=1
fi

if (( needs_build )); then
    if ! "$ROOT_DIR/scripts/build-app.sh" >>"$LOG_PATH" 2>&1; then
        /usr/bin/osascript -e 'display alert "AgentHUD 启动失败" message "应用构建失败，请查看 ~/Library/Logs/AgentHUD/launcher.log。" as critical'
        exit 1
    fi
fi

/usr/bin/open -g "$APP_PATH"
