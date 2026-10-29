"""viz の ASCII 出力：spec の各ステップの「到達状態」を文字の図にして stdout へ出す。

HTML 版と同じ spec を読む。補間はしない（ステップごとのコマ）。
全角文字（East Asian Width が W/F）は 2 マスとして数えるので、普通のターミナルでは枠が揃う。
Orca の会話ビューのように全角が 2 マスちょうどにならないフォントでは、日本語入りの枠はずれる。
"""
import math
import re
import unicodedata

WIDE = ("W", "F")
PAD = "\0"  # 全角文字の右半分（出力時に捨てる）


def cw(ch):
    return 2 if unicodedata.east_asian_width(ch) in WIDE else 1


def sw(s):
    return sum(cw(c) for c in s)


def fit(s, width):
    """表示幅 width に収まるよう末尾を … で切る。"""
    if sw(s) <= width:
        return s
    out, w = "", 0
    for c in s:
        if w + cw(c) > width - 1:
            break
        out, w = out + c, w + cw(c)
    return out + "…"


class Canvas:
    LINE = set("─│┄┆━┃┌┐└┘├┤┬┴┼╭╮╰╯▶◀▲▼·")

    def __init__(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.g = [[" "] * cols for _ in range(rows)]
        self.solid = set()  # 箱の枠と中身。線（soft）はここを踏まない

    def inside(self, r, c):
        return 0 <= r < self.rows and 0 <= c < self.cols

    def put(self, r, c, ch, soft=False):
        """soft=True は線：空白か他の線の上にだけ書く（箱や文字を潰さない）。"""
        if not self.inside(r, c):
            return
        if soft and ((r, c) in self.solid or (self.g[r][c] not in self.LINE and self.g[r][c] != " ")):
            return
        # 全角の片割れを踏んだら相方も消す
        if self.g[r][c] == PAD and c > 0:
            self.g[r][c - 1] = " "
        if c + 1 < self.cols and self.g[r][c + 1] == PAD:
            self.g[r][c + 1] = " "
        self.g[r][c] = ch
        if cw(ch) == 2 and c + 1 < self.cols:
            self.g[r][c + 1] = PAD

    def text(self, r, c, s, align="start"):
        w = sw(s)
        if align == "middle":
            c -= w // 2
        elif align == "end":
            c -= w
        for ch in s:
            self.put(r, c, ch)
            c += cw(ch)

    def clear(self, r0, c0, r1, c1):
        for r in range(r0, r1 + 1):
            for c in range(c0, c1 + 1):
                self.put(r, c, " ")
                self.solid.add((r, c))

    def lines(self):
        return ["".join(ch for ch in row if ch != PAD).rstrip() for row in self.g]


def strip_md(s):
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
    return re.sub(r"`([^`]+)`", r"\1", s)


def states(spec):
    """各ステップの到達状態（要素 id → props）を順に返す。"""
    cur = {e["id"]: dict(e) for e in spec["elements"]}
    for st in spec["steps"]:
        for eid, props in (st.get("set") or {}).items():
            for k, v in props.items():
                if isinstance(v, dict) and isinstance(cur[eid].get(k), dict):
                    cur[eid][k] = {**cur[eid][k], **v}
                else:
                    cur[eid][k] = v
        yield {k: dict(v) for k, v in cur.items()}


def visible(e, step):
    if "show" in e and step < e["show"]:
        return False
    if "hide" in e and step >= e["hide"]:
        return False
    return e.get("opacity", 1) > 0.05


def dim(e):
    return e.get("opacity", 1) < 0.5


def render(spec, cols=100):
    W, H = spec.get("width", 1000), spec.get("height", 560)
    rows = max(8, round(cols * H / W / 2))  # 文字は縦長（約 1:2）
    sx, sy = cols / W, rows / H
    X = lambda x: math.floor(x * sx + 0.5)  # round() は .5 を偶数へ寄せて行がぶれるので使わない
    Y = lambda y: math.floor(y * sy + 0.5)
    n = len(spec["steps"])
    frames = []

    for i, st in enumerate(states(spec)):
        step = i + 1
        cv = Canvas(cols, rows)
        geo = {}  # id → (r0, c0, r1, c1) 箱の外周（矢印の吸着用）
        arrays = {}  # id → (row, [セル中心の列], 下端の行)
        growers = set()  # ラベルのために広げた箱
        label_of = {}  # 箱 id → 実際に描くラベル行

        # 先に形の外周を決める（矢印が後ろの要素を参照できるように）
        for e in spec["elements"]:
            s = st[e["id"]]
            t = s["type"]
            if t in ("box", "circle"):
                hw = s["w"] / 2 if t == "box" else s["r"]
                hh = s["h"] / 2 if t == "box" else s["r"]
                rc, cc = Y(s["y"]), X(s["x"])
                labels = str(s.get("label", "")).split("\n") if s.get("label") else []
                vh = max(1, math.floor(hh * sy + 0.5))
                if 2 * vh - 1 < len(labels):  # 縦に入らない複数行ラベルは1行にまとめる（箱を伸ばすと隣とぶつかる）
                    labels = [" ".join(labels)]
                label_of[e["id"]] = labels
                r0, r1 = rc - vh, rc + vh
                c0, c1 = X(s["x"] - hw), X(s["x"] + hw)
                need = max((sw(l) for l in labels), default=0) + 4
                grown = c1 - c0 + 1 < need
                if grown:  # ラベルが収まるよう左右に広げる
                    grow = need - (c1 - c0 + 1)
                    c0 -= grow // 2
                    c1 += grow - grow // 2
                geo[e["id"]] = (r0, c0, r1, c1)
                if grown:
                    growers.add(e["id"])

        for gid in growers:
            r0, c0, r1, c1 = geo[gid]
            for oid, (q0, d0, q1, d1) in geo.items():
                if oid == gid or r1 < q0 or q1 < r0 or c1 < d0 or d1 < c0:
                    continue
                if (d0 + d1) < (c0 + c1):  # 相手が左 → 右へ
                    shift = d1 + 1 - c0
                else:  # 相手が右 → 左へ
                    shift = -(c1 + 1 - d0)
                c0, c1 = c0 + shift, c1 + shift
            geo[gid] = (r0, c0, r1, c1)

        def anchor(ref, toward):
            name, _, idx = str(ref).partition(":")
            if idx and name in arrays:
                row, centers, bottom = arrays[name]
                k = min(max(int(float(idx)), 0), len(centers) - 1)
                return (row - 1 if toward[0] < row else bottom + 1), centers[k]
            if name in geo:
                r0, c0, r1, c1 = geo[name]
                cr, cc = (r0 + r1) / 2, (c0 + c1) / 2
                dr, dc = toward[0] - cr, toward[1] - cc
                if abs(dc) * (r1 - r0 + 1) >= abs(dr) * (c1 - c0 + 1):
                    return round(cr), (c1 + 1 if dc > 0 else c0 - 1)
                return (r1 + 1 if dr > 0 else r0 - 1), round(cc)
            s = st.get(name)
            if s and "x" in s:
                return Y(s["y"]), X(s["x"])
            return toward

        def center_of(ref):
            name = str(ref).partition(":")[0]
            if name in geo:
                r0, c0, r1, c1 = geo[name]
                return (r0 + r1) / 2, (c0 + c1) / 2
            s = st.get(name, {})
            return Y(s.get("y", 0)), X(s.get("x", 0))

        for e in spec["elements"]:
            s = st[e["id"]]
            t = s["type"]
            if not visible(s, step):
                if t == "array":
                    arrays[e["id"]] = _array_geom(s, X, Y)
                continue
            d = dim(s)

            if t in ("box", "circle"):
                r0, c0, r1, c1 = geo[e["id"]]
                heavy = s.get("strokeWidth", 1) >= 3 and not d
                if t == "circle":
                    tl, tr, bl, br, hz, vt = "╭", "╮", "╰", "╯", "─", "│"
                elif heavy:
                    tl, tr, bl, br, hz, vt = "┏", "┓", "┗", "┛", "━", "┃"
                else:
                    tl, tr, bl, br, hz, vt = "┌", "┐", "└", "┘", "─", "│"
                if d or s.get("dash"):
                    hz, vt = "┄", "┆"
                cv.clear(r0, c0, r1, c1)
                for c in range(c0 + 1, c1):
                    cv.put(r0, c, hz)
                    cv.put(r1, c, hz)
                for r in range(r0 + 1, r1):
                    cv.put(r, c0, vt)
                    cv.put(r, c1, vt)
                cv.put(r0, c0, tl); cv.put(r0, c1, tr); cv.put(r1, c0, bl); cv.put(r1, c1, br)
                labels = label_of.get(e["id"], [])
                top = (r0 + r1) // 2 - (len(labels) - 1) // 2
                for k, l in enumerate(labels):
                    cv.text(top + k, (c0 + c1 + 1) // 2, fit(l, c1 - c0 - 1), "middle")

            elif t in ("text", "number"):
                if t == "number":
                    v = float(s["value"])
                    dec = s.get("decimals", 0)
                    body = f"{v:.{dec}f}" if dec else str(round(v))
                    txt = f"{s.get('prefix', '')}{body}{s.get('suffix', '')}"
                else:
                    txt = str(s["text"])
                if txt:
                    cv.text(Y(s["y"]), X(s["x"]), txt, s.get("align", "middle" if t == "text" else "start"))

            elif t == "arrow":
                p_from = (Y(s["y1"]), X(s["x1"])) if "x1" in s else None
                p_to = (Y(s["y2"]), X(s["x2"])) if "x2" in s else None
                if p_from is None:
                    p_from = anchor(s["from"], p_to or center_of(s["to"]))
                if p_to is None:
                    p_to = anchor(s["to"], p_from)
                if "from" in s and "x1" not in s:
                    p_from = anchor(s["from"], p_to)
                vf = False
                if "from" in s and "x1" not in s:
                    g = geo.get(str(s["from"]).partition(":")[0])
                    vf = bool(g) and not (g[0] <= p_from[0] <= g[2])  # 始点が箱の上か下 → 縦から
                if "to" in s and "x2" not in s and p_from[0] != p_to[0] and p_from[1] != p_to[1]:
                    tr, tc = center_of(s["to"])
                    # L 字の最後の区間の向きで箱に入るよう、終点を付け直す
                    p_to = anchor(s["to"], (tr, p_from[1]) if vf else (p_from[0], tc))
                _arrow(cv, p_from, p_to, s, d, vf)

            elif t == "code":
                _code(cv, s, X, Y)

            elif t == "array":
                arrays[e["id"]] = _array(cv, s, X, Y)

            elif t == "pointer":
                a = arrays.get(s["array"])
                if a:
                    row, centers, bottom = a
                    k = round(s["index"])
                    if 0 <= k < len(centers):
                        c = centers[k]
                        lab = str(s.get("label", ""))
                        if s.get("side", "top") == "top":
                            cv.text(row - 3, c, lab, "middle")  # row-1 は配列の上枠
                            cv.put(row - 2, c, "↓")
                        else:
                            cv.put(bottom + 1, c, "↑")
                            cv.text(bottom + 2, c, lab, "middle")

            elif t == "plot":
                _plot(cv, s, X, Y, st, step)

        cap = strip_md(spec["steps"][i].get("caption", ""))
        frames.append((step, cv.lines(), cap))

    # 全コマ共通で上下の空行を落とす（コマ間で図の位置が揃うように）
    used = [k for _, ls, _ in frames for k, l in enumerate(ls) if l.strip()]
    lo, hi = (min(used), max(used)) if used else (0, -1)
    title = spec.get("title", "")
    out = []
    for step, ls, cap in frames:
        head = f"── {title}  step {step}/{n} "
        out.append(head + "─" * max(4, cols - sw(head)))
        out.extend(ls[lo:hi + 1])
        if cap:
            out.append("")
            out.extend("  " + l for l in _wrap(cap, cols - 2))
        out.append("")
    return "\n".join(out)


def _wrap(s, width):
    out, line, w = [], "", 0
    for ch in s:
        if w + cw(ch) > width:
            out.append(line.rstrip())
            line, w = "", 0
        line, w = line + ch, w + cw(ch)
    if line.strip():
        out.append(line.rstrip())
    return out


def _arrow(cv, a, b, s, d, vertical_first=False):
    (r0, c0), (r1, c1) = a, b
    heavy = s.get("width", 2) >= 4 and not d
    hz = "┄" if (d or s.get("dash")) else ("━" if heavy else "─")
    vt = "┆" if (d or s.get("dash")) else ("┃" if heavy else "│")
    if r0 == r1 or c0 == c1:
        path = _seg(r0, c0, r1, c1)
        segs = [path]
    elif vertical_first:  # 箱の上下から出る：縦に出てから横へ
        s1, s2 = _seg(r0, c0, r1, c0), _seg(r1, c0, r1, c1)
        path, segs = s1 + s2[1:], [s1, s2]
    else:  # 箱の左右から出る：横に出てから縦へ
        s1, s2 = _seg(r0, c0, r0, c1), _seg(r0, c1, r1, c1)
        path, segs = s1 + s2[1:], [s1, s2]
    for k, (r, c) in enumerate(path):
        if k > 0 and k < len(path) - 1:
            pr, pc = path[k - 1]
            nr, nc = path[k + 1]
            if pr != nr and pc != nc:  # 曲がり角
                up = min(pr, nr) < r
                left = min(pc, nc) < c
                ch = {(True, True): "┘", (True, False): "└", (False, True): "┐", (False, False): "┌"}[(up, left)]
                cv.put(r, c, ch, soft=True)
                continue
        horiz = (k + 1 < len(path) and path[k + 1][0] == r) or (k > 0 and path[k - 1][0] == r)
        cv.put(r, c, hz if horiz else vt, soft=True)
    while len(path) >= 2 and path[-1] in cv.solid:
        path = path[:-1]
    if s.get("head", True) and len(path) >= 2:
        (pr, pc), (r, c) = path[-2], path[-1]
        cv.put(r, c, "▶" if c > pc else "◀" if c < pc else "▼" if r > pr else "▲", soft=True)
    lab = s.get("label")
    if lab and path:
        seg = max(segs, key=len)  # 一番長い区間の真ん中に置く（曲がり角を潰さない）
        r, c = seg[len(seg) // 2]
        if seg[0][0] == seg[-1][0]:
            cv.text(r - 1, c, str(lab), "middle")
        else:
            cv.text(r, c + 2, str(lab), "start")


def _seg(r0, c0, r1, c1):
    n = max(abs(r1 - r0), abs(c1 - c0))
    if n == 0:
        return [(r0, c0)]
    return [(round(r0 + (r1 - r0) * k / n), round(c0 + (c1 - c0) * k / n)) for k in range(n + 1)]


def _code(cv, s, X, Y):
    r, c = Y(s["y"]), X(s["x"])
    if s.get("title"):
        cv.text(r, c, f"# {s['title']}")
        r += 1
    hl = s.get("hl", 0)
    nums = s.get("lineNumbers", True)
    for k, line in enumerate(s["lines"], 1):
        mark = "▶" if k == hl else " "
        prefix = f"{mark}{k:>2} " if nums else f"{mark} "
        cv.text(r + k - 1, c, prefix + line)


def _array_geom(s, X, Y):
    vals = [str(v) for v in s["values"]]
    cell = max(sw(v) for v in vals) + 2
    r, c = Y(s["y"]), X(s["x"])
    if s.get("label"):
        c += sw(str(s["label"])) + 1
    centers = [c + 1 + k * (cell + 1) + cell // 2 for k in range(len(vals))]
    return r + 1, centers, r + 1


def _array(cv, s, X, Y):
    vals = [str(v) for v in s["values"]]
    order = s.get("order", list(range(len(vals))))
    cell = max(sw(v) for v in vals) + 2
    r, c = Y(s["y"]), X(s["x"])
    if s.get("label"):
        cv.text(r + 1, c, str(s["label"]))
        c += sw(str(s["label"])) + 1
    n = len(vals)
    top = "┌" + "┬".join("─" * cell for _ in range(n)) + "┐"
    bot = "└" + "┴".join("─" * cell for _ in range(n)) + "┘"
    cv.text(r, c, top)
    cv.text(r + 2, c, bot)
    fills = s.get("cellFill", {})
    marks = {"hl": "^", "accent": "^", "ok": "✓", "bad": "×", "warn": "!", "muted": "·", "line": "·"}  # 色の代わりにセルの下へ印
    centers = []
    for pos, orig in enumerate(order):
        x0 = c + 1 + pos * (cell + 1)
        cv.put(r + 1, x0 - 1, "│")
        v = vals[orig]
        cv.text(r + 1, x0 + (cell - sw(v) + 1) // 2, v)
        centers.append(x0 + cell // 2)
        m = marks.get(fills.get(str(orig), ""), "")
        if m:
            cv.put(r + 3, x0 + cell // 2, m)
    cv.put(r + 1, c + n * (cell + 1), "│")
    bottom = r + 2
    if s.get("showIndex", True):
        base = s.get("indexBase", 0)
        row = r + 4 if fills else r + 3
        for pos in range(n):
            cv.text(row, centers[pos], str(pos + base), "middle")
        bottom = row
    return r + 1, centers, bottom


def _plot(cv, s, X, Y, st, step):
    r0, c0 = Y(s["y"]), X(s["x"])
    r1, c1 = Y(s["y"] + s["h"]), X(s["x"] + s["w"])
    (xa, xb), (ya, yb) = s["xr"], s["yr"]
    for r in range(r0, r1 + 1):
        cv.put(r, c0, "│")
    for c in range(c0, c1 + 1):
        cv.put(r1, c, "─")
    cv.put(r1, c0, "└")
    fmt = lambda v: f"{v:g}"
    cv.text(r1 + 1, c0, fmt(xa))
    cv.text(r1 + 1, c1, fmt(xb), "end")
    cv.text(r0, c0 - 1, fmt(yb), "end")
    cv.text(r1, c0 - 1, fmt(ya), "end")
    if s.get("xlabel"):
        cv.text(r1 + 1, (c0 + c1) // 2, str(s["xlabel"]), "middle")
    if s.get("ylabel"):
        cv.text(r0 - 1, c0, str(s["ylabel"]))
    to_c = lambda x: c0 + 1 + round((x - xa) / (xb - xa) * (c1 - c0 - 1))
    to_r = lambda y: r1 - 1 - round((y - ya) / (yb - ya) * (r1 - r0 - 1))
    pid = s["id"]
    for e in st.values():
        if e.get("plot") != pid or not visible(e, step):
            continue
        if e["type"] == "curve":
            pts = []
            if "points" in e:
                pts = [tuple(p) for p in e["points"]]
            else:
                f = _js_fn(e["fn"], e.get("params", {}))
                cols = c1 - c0 - 1
                for k in range(cols + 1):
                    x = xa + (xb - xa) * k / cols
                    try:
                        y = f(x)
                    except Exception:
                        continue
                    if isinstance(y, (int, float)) and math.isfinite(y):
                        pts.append((x, y))
            reveal = e.get("reveal", 1)
            pts = [p for p in pts if p[0] <= xa + (xb - xa) * reveal]
            for x, y in pts:
                if ya <= y <= yb and xa <= x <= xb:
                    cv.put(to_r(y), to_c(x), "•")
        elif e["type"] == "dot":
            x, y = e["px"], e["py"]
            if xa <= x <= xb and ya <= y <= yb:
                r, c = to_r(y), to_c(x)
                if e.get("guides"):
                    for rr in range(r + 1, r1):
                        cv.put(rr, c, "┆", soft=True)
                    for cc in range(c0 + 1, c):
                        cv.put(r, cc, "┄", soft=True)
                cv.put(r, c, "●")
                if e.get("label"):
                    cv.text(r, c + 2, str(e["label"]))


_MATH = {k: getattr(math, k) for k in dir(math) if not k.startswith("_")}
_MATH.update(abs=abs, min=min, max=max, PI=math.pi, E=math.e)


def _js_fn(expr, params):
    """plot の fn（x の JS 式、Math. 省略）を Python で評価する。三項演算子など JS 固有の構文は非対応。"""
    py = expr.replace("Math.", "").replace("===", "==").replace("&&", " and ").replace("||", " or ")
    code = compile(py, "<fn>", "eval")
    return lambda x: eval(code, {"__builtins__": {}}, {**_MATH, **params, "x": x})
