#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_SDK="${SDKROOT:-$(xcrun --show-sdk-path)}"
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
 TASK_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
mkdir -p "$TASK_ROOT/.build/clang-cache"
xcrun swiftc -sdk "$TASK_SDK" -module-cache-path "$TASK_ROOT/.build/clang-cache" \
  -D STANDALONE_TESTS -o "$TASK_ROOT/.build/test-return-to-mac" \
  "$TASK_ROOT/PersonalControlCenter/Core/DeviceStatus.swift" \
  "$TASK_ROOT/PersonalControlCenter/Services/ReturnToMacRule.swift" \
  "$TASK_ROOT/PersonalControlCenter/Modules/Display/DDCPacket.swift" \
  "$TASK_ROOT/PersonalControlCenter/Modules/Display/DisplayCalibration.swift" \
  "$TASK_ROOT/PersonalControlCenter/Modules/PS5/PS5Service.swift" \
  "$TASK_ROOT/PersonalControlCenter/Modules/PS5/PS5PollingPolicy.swift" \
  "$TASK_ROOT/Tests/ReturnToMacTests.swift" \
  "$TASK_ROOT/script/ReturnToMacTestMain.swift"
"$TASK_ROOT/.build/test-return-to-mac"
