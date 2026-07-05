#!/bin/bash
# Test runner for the Groo iOS app.
# usage: scripts/test.sh [--unit|--ui|--all] [--coverage]   (default: --unit)
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="--unit"
COVERAGE=0
for arg in "$@"; do
  case "$arg" in
    --unit|--ui|--all) MODE="$arg" ;;
    --coverage) COVERAGE=1 ;;
    *) echo "usage: $0 [--unit|--ui|--all] [--coverage]"; exit 1 ;;
  esac
done

# PassAPIClientTests and PassServiceIntegrationTests share static test-infra
# state (StubURLProtocol's request queues) and are nested under the shared
# NetworkStubbedSuites(.serialized) umbrella so they serialize relative to
# each other; no global parallelism override is needed here.
ARGS=(test -project Groo.xcodeproj -scheme Groo
      -destination "platform=iOS Simulator,name=iPhone 17 Pro")

case "$MODE" in
  --unit) ARGS+=(-only-testing:GrooTests) ;;
  --ui)   ARGS+=(-only-testing:GrooUITests) ;;
  --all)  ;;
esac

RESULT_BUNDLE=""
if [ "$COVERAGE" = 1 ]; then
  RESULT_BUNDLE="build/coverage/$(date +%Y%m%d-%H%M%S).xcresult"
  mkdir -p build/coverage
  ARGS+=(-enableCodeCoverage YES -resultBundlePath "$RESULT_BUNDLE")
fi

xcodebuild "${ARGS[@]}"

if [ "$COVERAGE" = 1 ]; then
  echo
  echo "=== Coverage by target ==="
  xcrun xccov view --report --only-targets "$RESULT_BUNDLE"
  echo
  echo "=== Groo.app files with coverage (sorted, zero-coverage files omitted) ==="
  xcrun xccov view --report --files-for-target Groo.app "$RESULT_BUNDLE" \
    | grep '\.swift ' | grep -v ' 0\.00% ' | sort -t'(' -k2 -rn
  echo
  echo "Full result bundle: $RESULT_BUNDLE (open with: xed $RESULT_BUNDLE)"
fi
