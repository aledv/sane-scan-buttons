#!/usr/bin/env python3
"""Watches the front-panel buttons of a SANE scanner and runs action.sh for each press.

Most scanners report a button only while it is held down, so the device stays open and its
button "sensors" are polled every POLL seconds. The scanner can be shared with a web UI
(e.g. scanservjs) through saned: on a SANE connection saned-wrap.sh sends SIGUSR1, this daemon
closes the device and writes /run/scanner-released, then reopens it on SIGUSR2.

Environment:
  SANE_DEVICE_PREFIX  device name prefix to use (default: first device found, e.g. "genesys:")
  BUTTONS             comma-separated SANE button option names (default "scan,file,email,copy")
  POLL_SECONDS        polling interval (default 0.15)
"""

import os
import signal
import subprocess
import sys
import time

BUTTONS = tuple(b.strip() for b in os.environ.get("BUTTONS", "scan,file,email,copy").split(",") if b.strip())
POLL = float(os.environ.get("POLL_SECONDS") or 0.15)
DEVICE_PREFIX = os.environ.get("SANE_DEVICE_PREFIX", "")
PID_FILE = "/run/scanner-buttons.pid"
RELEASED_FLAG = "/run/scanner-released"
ACTION = os.environ.get("ACTION_SCRIPT", "/app/action.sh")

released = False


def log(msg: str) -> None:
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def newly_pressed(last: dict, current: dict) -> list:
    """Buttons that are down now and were up at the previous poll (one action per press)."""
    return [b for b in current if current[b] and not last.get(b)]


def pick_device(devices: list, prefix: str = "") -> str | None:
    names = [d[0] for d in devices]
    matching = [n for n in names if n.startswith(prefix)] if prefix else names
    return matching[0] if matching else None


def _on_release(*_):
    global released
    released = True


def _on_resume(*_):
    global released
    released = False


def main() -> int:
    import sane  # python3-sane, only available in the image

    signal.signal(signal.SIGUSR1, _on_release)
    signal.signal(signal.SIGUSR2, _on_resume)
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
    sane.init()
    dev = name = None
    last = dict.fromkeys(BUTTONS, 0)
    while True:
        if released:
            if dev:
                dev.close()
                dev = None
                open(RELEASED_FLAG, "w").close()
                log("scanner handed over to saned")
            time.sleep(0.2)
            continue
        if os.path.exists(RELEASED_FLAG):
            os.remove(RELEASED_FLAG)
        if dev is None:
            try:
                sane.exit()
                sane.init()
                name = pick_device(sane.get_devices(), DEVICE_PREFIX)
                if not name:
                    time.sleep(5)
                    continue
                dev = sane.open(name)
                missing = [b for b in BUTTONS if b not in dev.opt]
                if missing:
                    log(f"warning: {name} has no button option(s) {missing}; check BUTTONS (scanimage -A lists them)")
                log(f"watching buttons {list(BUTTONS)} on {name}")
            except Exception as e:
                log(f"cannot open the scanner ({e}), retrying")
                dev = None
                time.sleep(2)
                continue
        try:
            current = {b: dev.dev.get_option(dev.opt[b].index) for b in BUTTONS if b in dev.opt}
        except Exception as e:
            log(f"read failed ({e}), reopening")
            try:
                dev.close()
            except Exception:
                pass
            dev = None
            time.sleep(1)
            continue
        pressed = newly_pressed(last, current)
        last = current
        if pressed:
            button = pressed[0]
            log(f"button {button}")
            dev.close()  # action.sh needs the scanner for scanimage
            dev = None
            subprocess.run([ACTION], env=dict(os.environ, SCANBD_ACTION=button, SCANBD_DEVICE=name))
            last = dict.fromkeys(BUTTONS, 0)
            continue
        time.sleep(POLL)


if __name__ == "__main__":
    sys.exit(main())
