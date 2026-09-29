#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_SDK="${SDKROOT:-$(xcrun --show-sdk-path)}"
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
 TASK_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
mkdir -p "$TASK_ROOT/.build/diagnostic-module-cache"
xcrun swiftc -sdk "$TASK_SDK" -module-cache-path "$TASK_ROOT/.build/diagnostic-module-cache" \
 "$TASK_ROOT/script/ModeReapply/Core.swift" "$TASK_ROOT/script/RefreshPulse/PulseModel.swift" \
 "$TASK_ROOT/Tests/RefreshPulseTests.swift" -o "$TASK_ROOT/.build/test-refresh-pulse"
"$TASK_ROOT/.build/test-refresh-pulse"
bash "$TASK_ROOT/script/probe_refresh_pulse.sh" --help
for invalid in '--apply-once' '--unknown' '--help --apply-once' '--apply-once --apply-once' '--check-guardian --apply-once'; do
 read -r -a invalid_args <<< "$invalid"
 if "$TASK_ROOT/.build/probe-refresh-pulse" "${invalid_args[@]}"; then
   echo "FAIL: accepted invalid args: $invalid" >&2; exit 1
 fi
done
echo 'PASS: 5 invalid CLI invocations refused before display access'
