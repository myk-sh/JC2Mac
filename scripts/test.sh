#!/bin/bash
set -euo pipefail
exec "$(dirname "$0")/swift-tool.sh" test "$@"
