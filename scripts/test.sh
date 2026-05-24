#!/usr/bin/env bash
# Run the ConduitKit engine test suite on macOS.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
cd Packages/ConduitKit
swift test "$@"
