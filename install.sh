#!/bin/bash
# Run as the logged-in user. No username substitution, sudo or Keychain changes.
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(id -u)" = 0 ]; then
    echo 'Run as your macOS login user, without sudo.' >&2
    exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${LAZYMOUNT_PYTHON:-$(command -v python3 || true)}"
if [ -z "$PYTHON_BIN" ] || ! "$PYTHON_BIN" -c 'import sys; assert sys.version_info >= (3,9)' 2>/dev/null; then
    echo 'Python 3.9+ is required. Install Python from python.org or Homebrew, then retry.' >&2
    exit 1
fi
exec "$PYTHON_BIN" "$SCRIPT_DIR/install.py" "${1:-install}"
