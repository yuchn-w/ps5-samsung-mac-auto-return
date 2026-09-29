#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_SDK="${SDKROOT:-$(xcrun --show-sdk-path)}"
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
 TASK_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
mkdir -p "$TASK_ROOT/.build/diagnostic-module-cache"
TASK_STAGING="$(mktemp -d "$TASK_ROOT/.build/refresh-build.XXXXXX")"
trap 'rmdir "$TASK_STAGING" 2>/dev/null || true' EXIT
xcrun swiftc -sdk "$TASK_SDK" -module-cache-path "$TASK_ROOT/.build/diagnostic-module-cache" \
 "$TASK_ROOT/script/ModeReapply/Core.swift" "$TASK_ROOT/script/RefreshPulse/PulseModel.swift" \
 "$TASK_ROOT/script/RefreshPulse/main.swift" -o "$TASK_STAGING/probe-refresh-pulse"
mv "$TASK_STAGING/probe-refresh-pulse" "$TASK_ROOT/.build/probe-refresh-pulse"
"$TASK_ROOT/.build/probe-refresh-pulse" "$@"
