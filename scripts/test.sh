#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$ROOT_DIR/.build/adapter-self-test"

cd "$ROOT_DIR"

swiftc \
    Sources/AgentHUD/AIConfiguration.swift \
    Sources/AgentHUD/KeychainAISecretStore.swift \
    Sources/AgentHUD/AITitleService.swift \
    Sources/AgentHUD/Models.swift \
    Sources/AgentHUD/Utilities.swift \
    Sources/AgentHUD/SessionTitleStore.swift \
    Sources/AgentHUD/SessionImportanceStore.swift \
    Sources/AgentHUD/CodexAdapter.swift \
    Sources/AgentHUD/ClaudeAdapter.swift \
    Sources/AgentHUD/OpenCodeAdapter.swift \
    Sources/AgentHUD/OpenCodeSessionSource.swift \
    Sources/AgentHUD/OrcaSessionSource.swift \
    Sources/AgentHUD/LinkModels.swift \
    Sources/AgentHUD/LinkDeviceStore.swift \
    Sources/AgentHUD/LinkPairingManager.swift \
    Sources/AgentHUD/LinkCertificate.swift \
    Sources/AgentHUD/AgentInputAdapter.swift \
    Sources/AgentHUD/AgentRuntimeRegistry.swift \
    Sources/AgentHUD/DeliveryStore.swift \
    Sources/AgentHUD/CodexInputAdapter.swift \
    Sources/AgentHUD/AgentInputDispatcher.swift \
    Tests/LinkTests.swift \
    Tests/main.swift \
    -o "$BINARY"

"$BINARY"
