#!/usr/bin/env bash
# Build the SwiftPM package. Use xcodebuild + a simulator to compile the
# iOS-only feature modules and the app target.
#
# Local agent/simulator work: acquire a Simurgh lease and route iOS builds through
#   simurgh exec <lease-id> -- xcodebuild …
# (see AGENTS.md). This script is a convenience for engines-only SPM builds and
# bare xcodebuild ios — not the governed sim path.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

case "${1:-engines}" in
  engines)
    cd Packages/LancerKit
    swift build
    ;;
  ios)
    if ! command -v xcodegen >/dev/null; then
      echo "xcodegen not found; install with: brew install xcodegen" >&2
      exit 1
    fi
    xcodegen
    xcodebuild -project Lancer.xcodeproj \
      -scheme Lancer \
      -configuration Debug \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      build
    ;;
  *)
    echo "usage: $0 [engines|ios]" >&2
    exit 2
    ;;
esac
