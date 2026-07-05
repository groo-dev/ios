#!/bin/bash
# Test runner for the Groo iOS app.
# usage: scripts/test.sh [--unit|--ui|--all]   (default: --unit)
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:---unit}"
# GrooTests suites share static test-infra state (e.g. StubURLProtocol's
# request queues) across suites, not just within one -- Swift Testing's
# default cross-suite parallelism races on that shared state, so tests are
# forced to run serially here.
ARGS=(test -project Groo.xcodeproj -scheme Groo
      -destination "platform=iOS Simulator,name=iPhone 17 Pro"
      -parallel-testing-enabled NO)

case "$MODE" in
  --unit) ARGS+=(-only-testing:GrooTests) ;;
  --ui)   ARGS+=(-only-testing:GrooUITests) ;;
  --all)  ;;
  *) echo "usage: $0 [--unit|--ui|--all]"; exit 1 ;;
esac

xcodebuild "${ARGS[@]}"
