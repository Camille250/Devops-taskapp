#!/usr/bin/env bash
# Runs once when the codespace is created.
set -euo pipefail
python3 -m pip install --user --quiet ansible-core
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
echo
echo "Codespace ready. Next: follow README Phase 0 (run: make help)."
