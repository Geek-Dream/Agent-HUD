#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR%/}/agent-hud-link-test.XXXXXX")"
FIXTURE="$WORK_DIR/fixture.json"
LOG="$WORK_DIR/server.log"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        /usr/bin/touch "$FIXTURE.stop"
        kill "$SERVER_PID" >/dev/null 2>&1 || true
        wait "$SERVER_PID" >/dev/null 2>&1 || true
        cat "$LOG"
    fi
    if [[ -z "${AGENTHUD_KEEP_FIXTURE:-}" ]]; then
        rm -rf "$WORK_DIR"
    else
        print "Fixture directory: $WORK_DIR"
    fi
}
trap cleanup EXIT INT TERM

cd "$ROOT_DIR"
BUILD_DIR="$ROOT_DIR/.build/out/Products/Debug"
module_args=()
/bin/cp "$ROOT_DIR/Tests/LinkFixtureMain.swift" "$WORK_DIR/main.swift"
for module_map in "$ROOT_DIR"/.build/out/Intermediates.noindex/GeneratedModuleMaps/*.modulemap \
    "$ROOT_DIR"/.build/checkouts/*/Sources/*/include/module.modulemap; do
    module_args+=(-Xcc "-fmodule-map-file=$module_map")
done
swiftc \
    -I "$BUILD_DIR" -L "$BUILD_DIR" "${module_args[@]}" \
    Sources/AgentHUD/Models.swift \
    Sources/AgentHUD/Utilities.swift \
    Sources/AgentHUD/CommandRunner.swift \
    Sources/AgentHUD/LinkModels.swift \
    Sources/AgentHUD/LinkDeviceStore.swift \
    Sources/AgentHUD/LinkPairingManager.swift \
    Sources/AgentHUD/LinkCertificate.swift \
    Sources/AgentHUD/LinkResponses.swift \
    Sources/AgentHUD/AgentInputAdapter.swift \
    Sources/AgentHUD/AgentRuntimeRegistry.swift \
    Sources/AgentHUD/DeliveryStore.swift \
    Sources/AgentHUD/CodexInputAdapter.swift \
    Sources/AgentHUD/AgentInputDispatcher.swift \
    Sources/AgentHUD/LinkServer.swift \
    Tests/LinkServerFixture.swift \
    "$WORK_DIR/main.swift" \
    "$BUILD_DIR"/*.o \
    -o "$WORK_DIR/link-server-fixture"

"$WORK_DIR/link-server-fixture" "$WORK_DIR/data" "$FIXTURE" >"$LOG" 2>&1 &
SERVER_PID=$!
for _ in {1..60}; do
    [[ -f "$FIXTURE" ]] && break
    if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
        cat "$LOG"
        exit 1
    fi
    sleep 0.25
done
if [[ ! -f "$FIXTURE" ]]; then
    cat "$LOG"
    exit 1
fi

(
    cd "$ROOT_DIR/mobile"
    AGENTHUD_LINK_FIXTURE="$FIXTURE" flutter test test/link_integration_test.dart
)
wait "$SERVER_PID"
SERVER_PID=""
cat "$LOG"
