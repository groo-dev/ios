#!/bin/bash
# Test runner for the Groo iOS app.
# usage: scripts/test.sh [--unit|--ui|--all]   (default: --unit)
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:---unit}"
ARGS=(test -project Groo.xcodeproj -scheme Groo
      -destination "platform=iOS Simulator,name=iPhone 17 Pro")

case "$MODE" in
  --unit) ARGS+=(-only-testing:GrooTests) ;;
  --ui)   ARGS+=(-only-testing:GrooUITests) ;;
  --all)  ;;
  *) echo "usage: $0 [--unit|--ui|--all]"; exit 1 ;;
esac

xcodebuild "${ARGS[@]}"
