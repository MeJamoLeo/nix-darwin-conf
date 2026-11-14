"""app-pad: summon an app as an OmniWM scratchpad window.

Usage: app-pad <scratchpad-number> <bundle-id>

  - The app's window is already in scratchpad N  -> toggle it (show / hide).
  - The app has a window outside the scratchpad  -> focus it, assign it to N, show it.
  - The app has no window (or is not running)    -> open it, wait for a window,
                                                    assign it to N, show it.

Uses omniwmctl only. Standard library only.
"""

import json
import os
import subprocess
import sys
import time

OMNIWMCTL = os.environ.get("APP_PAD_OMNIWMCTL", "omniwmctl")
WAIT_SECONDS = 15


def ctl(*args):
    out = subprocess.run([OMNIWMCTL, *args], capture_output=True, text=True)
    return out.stdout


def windows(bundle):
    raw = ctl("query", "windows", "--bundle-id", bundle,
              "--fields", "id,is-scratchpad,scratchpad-index,is-focused", "--format", "json")
    try:
        return json.loads(raw)["result"]["payload"]["windows"]
    except (ValueError, KeyError, TypeError):
        return []


def wait_until(check):
    deadline = time.time() + WAIT_SECONDS
    while time.time() < deadline:
        if check():
            return True
        time.sleep(0.2)
    return False


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    n, bundle = sys.argv[1], sys.argv[2]

    wins = windows(bundle)
    if any(w.get("isScratchpad") and str(w.get("scratchpadIndex")) == n for w in wins):
        ctl("command", "scratchpad", "toggle", n)
        return

    # Launch the app if it has no window, then focus its window by id.
    # (A freshly opened window is not always focused, so always focus explicitly.)
    if not wins:
        subprocess.run(["/usr/bin/open", "-b", bundle])
        if not wait_until(lambda: windows(bundle)):
            print(f"app-pad: {bundle} opened no window after {WAIT_SECONDS}s", file=sys.stderr)
            sys.exit(1)
        wins = windows(bundle)
    ctl("window", "focus", wins[0]["id"])
    if not wait_until(lambda: any(w.get("isFocused") for w in windows(bundle))):
        print(f"app-pad: no focused window for {bundle} after {WAIT_SECONDS}s", file=sys.stderr)
        sys.exit(1)
    ctl("command", "scratchpad", "assign", n)   # assigning hides the window
    ctl("command", "scratchpad", "toggle", n)   # so show it right away


if __name__ == "__main__":
    main()
