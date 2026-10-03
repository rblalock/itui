#!/usr/bin/env python3
"""Publish the current Omarchy palette to the configured itui server."""

import json
import os
from pathlib import Path
import sys
import tomllib
import urllib.request


def sync():
    home = Path.home()
    config_root = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    state_root = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    config = json.loads((config_root / "itui/omarchy-theme-sync.json").read_text())
    current = state_root / "omarchy/current"
    before = (current / "theme.name").read_text().strip()
    colors = tomllib.loads((current / "theme/colors.toml").read_text())
    name = (current / "theme.name").read_text().strip()
    if before != name:
        raise RuntimeError("Theme changed during sync; the next run will retry.")
    keys = {
        "mode", "accent", "background", "foreground", "selection",
        "selection_background", "selection_foreground", "red", "green",
        "yellow", "blue", "magenta", "cyan",
        "color1", "color2", "color3", "color4", "color5", "color6",
    }
    payload = json.dumps({"name": name, "colors": {
        key: value for key, value in colors.items() if key in keys
    }}).encode()
    request = urllib.request.Request(
        config["server_url"].rstrip("/") + "/api/theme",
        data=payload, headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        result = json.load(response)
    if result.get("theme", {}).get("colors") != json.loads(payload)["colors"]:
        raise RuntimeError("The server did not confirm the palette.")
    print(f"Synced itui to {name}")


if __name__ == "__main__":
    try:
        sync()
    except Exception as error:
        print(f"itui theme sync: {error}", file=sys.stderr)
        sys.exit(1)
