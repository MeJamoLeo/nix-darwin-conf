"""fm: a terminal player that drives mpv behind a "perfume bottle" Walkman-style screen.

Usage:
  fm                 play Claude FM
  fm skrillex        shuffle the top 20 YouTube results for "Skrillex"
  fm <URL>           play a URL (video or playlist) as-is
  fm <words>         search YouTube for <words> and shuffle the top 20 results

Talks to mpv over its JSON IPC socket. Standard library only.
"""

import curses
import json
import locale
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unicodedata

PRESETS = {
    "claude": ("https://www.youtube.com/watch?v=tRsQsTMvPNg", False),
    "skrillex": ("ytdl://ytsearch20:Skrillex", True),
}

KEYS = "space play/pause   ←/→ seek 10s   </> track   +/- volume   q quit"


# ---------- mpv ----------

class Mpv:
    def __init__(self, target, shuffle):
        self.sock_path = os.path.join(tempfile.mkdtemp(prefix="fm-"), "mpv.sock")
        args = [
            os.environ.get("FM_MPV", "mpv"),
            "--no-video", "--no-terminal", "--force-window=no",
            "--ytdl-format=bestaudio/best",
            f"--input-ipc-server={self.sock_path}",
        ]
        if shuffle:
            args.append("--shuffle")
        args.append(target)
        self.proc = subprocess.Popen(args, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.sock = None
        self.buf = b""
        self.req = 0

    def alive(self):
        return self.proc.poll() is None

    def _connect(self):
        if self.sock is not None:
            return True
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect(self.sock_path)
            self.sock = s
            return True
        except OSError:
            return False

    def command(self, *cmd):
        if not self._connect():
            return None
        self.req += 1
        rid = self.req
        try:
            self.sock.sendall(json.dumps({"command": list(cmd), "request_id": rid}).encode() + b"\n")
            deadline = time.time() + 0.5
            while time.time() < deadline:
                while b"\n" in self.buf:
                    line, self.buf = self.buf.split(b"\n", 1)
                    try:
                        msg = json.loads(line)
                    except ValueError:
                        continue
                    if msg.get("request_id") == rid:
                        return msg.get("data") if msg.get("error") == "success" else None
                chunk = self.sock.recv(65536)
                if not chunk:
                    break
                self.buf += chunk
        except OSError:
            self.sock = None
        return None

    def get(self, name):
        return self.command("get_property", name)

    def quit(self):
        try:
            self.command("quit")
        except Exception:
            pass
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.proc.kill()


# ---------- text width ----------

def cw(ch):
    return 2 if unicodedata.east_asian_width(ch) in "WF" else 1


def width(s):
    return sum(cw(c) for c in s)


def fit(s, w):
    """Cut s to display width w, padding with spaces if shorter."""
    out, n = "", 0
    for c in s:
        if n + cw(c) > w:
            break
        out += c
        n += cw(c)
    return out + " " * (w - n)


def marquee(s, w, tick):
    if width(s) <= w:
        return fit(s, w)
    loop = s + "   ◆   "
    i = tick % len(loop)
    return fit(loop[i:] + loop, w)


def mmss(t):
    if t is None:
        return "--:--"
    t = int(t)
    return f"{t // 3600}:{t // 60 % 60:02d}:{t % 60:02d}" if t >= 3600 else f"{t // 60:02d}:{t % 60:02d}"


# ---------- drawing ----------

DW = 42          # inner width of the LCD
BW = DW + 16     # inner width of the body (margin 2 + LCD + gap 3 + dial 7 + margin 2)

# Jog dial marker: steps through 8 positions as playback advances.
DIAL = [(0, 3), (0, 5), (1, 6), (2, 5), (2, 3), (2, 1), (1, 0), (0, 1)]


def bottle():
    """Outline of the bottle lying on its side, as a list of rows. Cap on the right."""
    neck = ["   ╭───╮", "───┤▒▒▒│", "   │▒▒▒│", "───┤▒▒▒│", "   ╰───╯"]
    edge = ["│", "├", "│", "├", "│"]
    rows = ["  ╭" + "─" * BW + "╮", " ╭╯" + " " * BW + "╰╮"]
    for k in range(5):
        rows.append(" │ " + " " * BW + " " + edge[k] + neck[k])
    rows += [" ╰╮" + " " * BW + "╭╯", "  ╰" + "─" * BW + "╯"]
    return rows


def draw(scr, st, tick, colors):
    scr.erase()
    H, W = scr.getmaxyx()
    rows = bottle()
    total_w = max(width(r) for r in rows)
    if H < len(rows) + 2 or W < total_w + 1:
        scr.addstr(0, 0, "Terminal too small"[: max(0, W - 1)])
        scr.refresh()
        return
    oy = max(0, (H - len(rows) - 2) // 2)
    ox = max(0, (W - total_w) // 2)
    glass, lcd, dim, hi = colors

    for i, r in enumerate(rows):
        scr.addstr(oy + i, ox, r, glass)

    # LCD (inside the body, left-aligned)
    wy, wx = oy + 2, ox + 5
    scr.addstr(wy, wx, "┌" + "─" * DW + "┐", dim)
    for k in range(3):
        scr.addstr(wy + 1 + k, wx, "│" + " " * DW + "│", dim)
    scr.addstr(wy + 4, wx, "└" + "─" * DW + "┘", dim)

    def put(line, text, attr=lcd):
        scr.addstr(wy + 1 + line, wx + 1, fit(" " + text, DW), attr)

    # While loading, mpv reports the search term or URL as the title, so wait for a time position.
    if st["title"] is None or st["time"] is None:
        put(0, "WALKMAN", hi)
        put(1, "LOADING" + "." * (tick // 3 % 4))
        put(2, "")
    else:
        mark = "❚❚" if st["pause"] else "▶ "
        cnt = st["count"] or 0
        tr = f"TR {(st['pos'] or 0) + 1:02d}/{cnt:02d}" if cnt > 1 else "TR 01"
        live = st["dur"] in (None, 0)
        clock = mmss(st["time"]) + ("  LIVE" if live else " / " + mmss(st["dur"]))
        vol = int(st["vol"] or 0)
        put(0, f"{mark} {tr}  {clock}", hi)
        scr.addstr(wy + 1, wx + DW - 10, f"VOL {'▮' * (vol // 20)}{'▯' * max(0, 5 - vol // 20)} ", lcd)
        put(1, marquee(st["title"], DW - 2, tick // 3))
        if live:
            put(2, "")
        else:
            bar_w = DW - 2
            frac = min(1.0, (st["time"] or 0) / st["dur"])
            fill = int(frac * bar_w)
            put(2, "━" * fill + "╸" + "─" * max(0, bar_w - fill - 1), dim)

    # Jog dial (right of the LCD)
    dy, dx = wy + 1, wx + DW + 2 + 3
    for k, r in enumerate(["╭─────╮", "│     │", "╰─────╯"]):
        scr.addstr(dy + k, dx, r, glass)
    scr.addstr(dy + 1, dx + 3, "●", hi)
    py, px = DIAL[int((st["time"] or 0) / 4) % len(DIAL)]
    scr.addstr(dy + py, dx + px, "◆", lcd)

    scr.addstr(oy + len(rows) + 1, max(0, (W - width(KEYS)) // 2), fit(KEYS, min(W - 1, width(KEYS))), dim)
    scr.refresh()


def init_colors():
    try:
        curses.start_color()
        curses.use_default_colors()
    except curses.error:
        return (0, 0, curses.A_DIM, curses.A_BOLD)
    if curses.COLORS >= 256:
        g, l, d, h = 153, 51, 31, 159   # pale blue glass / cyan LCD
    else:
        g = l = h = curses.COLOR_CYAN
        d = curses.COLOR_BLUE
    curses.init_pair(1, g, -1)
    curses.init_pair(2, l, -1)
    curses.init_pair(3, d, -1)
    curses.init_pair(4, h, -1)
    return (curses.color_pair(1), curses.color_pair(2),
            curses.color_pair(3), curses.color_pair(4) | curses.A_BOLD)


def state(mpv):
    return {
        "title": mpv.get("media-title"),
        "pause": mpv.get("pause"),
        "time": mpv.get("time-pos"),
        "dur": mpv.get("duration"),
        "vol": mpv.get("volume"),
        "pos": mpv.get("playlist-pos"),
        "count": mpv.get("playlist-count"),
    }


def run(scr, mpv):
    curses.curs_set(0)
    scr.timeout(150)
    colors = init_colors()
    tick = 0
    st = state(mpv)
    while mpv.alive():
        if tick % 2 == 0:
            st = state(mpv)
        draw(scr, st, tick, colors)
        key = scr.getch()
        tick += 1
        if key in (ord("q"), 27):
            break
        elif key == ord(" "):
            mpv.command("cycle", "pause")
        elif key in (curses.KEY_RIGHT, ord("l")):
            mpv.command("seek", 10)
        elif key in (curses.KEY_LEFT, ord("h")):
            mpv.command("seek", -10)
        elif key in (ord(">"), ord("n"), ord(".")):
            mpv.command("playlist-next")
        elif key in (ord("<"), ord("p"), ord(",")):
            mpv.command("playlist-prev")
        elif key in (ord("+"), ord("=")):
            mpv.command("add", "volume", 5)
        elif key == ord("-"):
            mpv.command("add", "volume", -5)
        else:
            continue
        st = state(mpv)


def main():
    arg = " ".join(sys.argv[1:]).strip() or "claude"
    if arg in ("-h", "--help"):
        print(__doc__)
        return
    if arg.lower() in PRESETS:
        target, shuffle = PRESETS[arg.lower()]
    elif "://" in arg:
        target, shuffle = arg, False
    else:
        target, shuffle = f"ytdl://ytsearch20:{arg}", True
    locale.setlocale(locale.LC_ALL, "")
    # Closing the terminal sends SIGHUP; turn it (and SIGTERM) into a normal exit
    # so the finally block below still stops mpv instead of leaving it playing.
    for sig in (signal.SIGHUP, signal.SIGTERM):
        signal.signal(sig, lambda *_: sys.exit(0))
    mpv = Mpv(target, shuffle)
    try:
        curses.wrapper(run, mpv)
    except KeyboardInterrupt:
        pass
    finally:
        mpv.quit()


if __name__ == "__main__":
    main()
