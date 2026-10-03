#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  echo "Usage: $0 <itui-server-url>" >&2
  exit 1
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/itui"
mkdir -p "$CONFIG_DIR/itui" "$CONFIG_DIR/systemd/user" "$DATA_DIR"
python3 - "$1" "$CONFIG_DIR/itui/omarchy-theme-sync.json" <<'PY'
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
if url.scheme not in {"http", "https"} or not url.hostname or url.username or url.query or url.fragment:
    raise SystemExit("Expected an HTTP(S) server URL without credentials, a query, or a fragment.")
Path(sys.argv[2]).write_text(json.dumps({"server_url": sys.argv[1].rstrip("/")}) + "\n")
PY

cp "$ROOT/scripts/omarchy-theme-sync.py" "$DATA_DIR/omarchy-theme-sync.py"
cat > "$CONFIG_DIR/systemd/user/itui-theme-sync.service" <<UNIT
[Unit]
Description=Sync the Omarchy palette to itui

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 "$DATA_DIR/omarchy-theme-sync.py"
Environment=XDG_CONFIG_HOME="$CONFIG_DIR"
Environment=XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
TimeoutStartSec=10
UNIT

# Remove the periodic sync from earlier installs. Only explicit theme changes
# should publish a palette when several machines use the same Mac server.
systemctl --user disable --now itui-theme-sync.timer 2>/dev/null || true
python3 - "$CONFIG_DIR/systemd/user/itui-theme-sync.timer" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).unlink(missing_ok=True)
PY

omarchy hook install theme-set "$ROOT/scripts/itui-theme-set-hook"
systemctl --user daemon-reload
systemctl --user start itui-theme-sync.service
echo "Theme sync installed. Select Follow Omarchy in itui's Settings → Theme."
