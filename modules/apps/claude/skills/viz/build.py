#!/usr/bin/env python3
"""viz: validate a scroll-driven diagram spec (JSON) and bake it into a self-contained HTML page.

usage: build.py SPEC.json [-o OUT.html] [--open] [--shot 1,2.5,4]
       build.py SPEC.json --ascii [--cols 100]
  default OUT is SPEC with .html suffix; --shot writes OUT-s<step>.png via headless Chrome.
  --ascii prints every step as a text frame to stdout instead (no HTML is written).
"""
import argparse, html, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOKENS = {"bg", "fg", "muted", "panel", "line", "accent", "ok", "warn", "bad", "hl", "none"}
COMMON = {"id", "type", "show", "hide", "opacity"}
TYPES = {
    "box":     ({"x", "y", "w", "h"}, {"label", "fill", "stroke", "strokeWidth", "rx", "labelSize", "labelColor", "dash"}),
    "circle":  ({"x", "y", "r"}, {"label", "fill", "stroke", "strokeWidth", "labelSize", "labelColor", "dash"}),
    "text":    ({"x", "y", "text"}, {"size", "color", "align", "weight"}),
    "number":  ({"x", "y", "value"}, {"decimals", "prefix", "suffix", "size", "color", "align", "weight"}),
    "arrow":   (set(), {"from", "to", "x1", "y1", "x2", "y2", "color", "width", "bend", "gap", "head", "dash", "label", "labelSize"}),
    "code":    ({"x", "y", "lines"}, {"w", "size", "hl", "hlColor", "lineNumbers", "title"}),
    "array":   ({"x", "y", "values"}, {"cell", "order", "cellFill", "showIndex", "indexBase", "label", "stroke", "size"}),
    "pointer": ({"array", "index"}, {"label", "side", "color", "dy"}),
    "plot":    ({"x", "y", "w", "h", "xr", "yr"}, {"grid", "ticks", "xlabel", "ylabel", "color"}),
    "curve":   ({"plot"}, {"fn", "points", "params", "reveal", "color", "width", "dash", "samples"}),
    "dot":     ({"plot", "px", "py"}, {"r", "color", "label", "guides"}),
}
COLOR_PROPS = {"fill", "stroke", "color", "labelColor", "hlColor"}
FROZEN_IN_STEPS = {"id", "type", "show", "hide", "array", "plot"}


def validate(spec):
    errs = []
    E = errs.append
    if not isinstance(spec.get("elements"), list) or not spec["elements"]:
        E("elements: 1 個以上必要")
        return errs
    if not isinstance(spec.get("steps"), list) or not spec["steps"]:
        E("steps: 1 個以上必要")
        return errs
    n_steps = len(spec["steps"])
    for k in spec:
        if k not in {"title", "slug", "width", "height", "ease", "elements", "steps"}:
            E(f"top-level: 未知のキー '{k}'")
    if spec.get("ease", "smooth") not in {"smooth", "linear"}:
        E("ease: smooth | linear")

    els = {}
    for i, e in enumerate(spec["elements"]):
        where = f"elements[{i}]"
        eid, typ = e.get("id"), e.get("type")
        if not isinstance(eid, str) or not eid:
            E(f"{where}: id が無い")
            continue
        if eid in els:
            E(f"{where}: id '{eid}' が重複")
        if typ not in TYPES:
            E(f"{where} ({eid}): 未知の type '{typ}'（{', '.join(TYPES)}）")
            continue
        req, opt = TYPES[typ]
        for k in req - e.keys():
            E(f"{eid}: 必須プロパティ '{k}' が無い")
        for k in ("show", "hide"):
            if k in e and not (isinstance(e[k], int) and 1 <= e[k] <= n_steps):
                E(f"{eid}.{k}: 1..{n_steps} の整数（ステップ番号は 1 始まり）")
        if typ == "arrow":
            if "from" not in e and not {"x1", "y1"} <= e.keys():
                E(f"{eid}: 始点に from か x1,y1 が要る")
            if "to" not in e and not {"x2", "y2"} <= e.keys():
                E(f"{eid}: 終点に to か x2,y2 が要る")
        if typ == "curve" and "fn" not in e and "points" not in e:
            E(f"{eid}: fn か points が要る")
        els[eid] = e

    def check_props(eid, props, where):
        e = els[eid]
        typ = e["type"]
        req, opt = TYPES[typ]
        for k, v in props.items():
            if k in FROZEN_IN_STEPS:
                E(f"{where}: '{k}' はステップで変えられない")
                continue
            if k not in req | opt | {"opacity"}:
                E(f"{where}: {typ} に未知のプロパティ '{k}'（typo?）")
            if k in COLOR_PROPS:
                check_color(v, f"{where}.{k}")
            if k == "cellFill":
                if not isinstance(v, dict):
                    E(f"{where}.cellFill: {{\"元のindex\": 色}} の形")
                else:
                    for ck, cv in v.items():
                        check_color(cv, f"{where}.cellFill[{ck}]")

    def check_color(v, where):
        if not isinstance(v, str) or not (v in TOKENS or re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", v)):
            E(f"{where}: 色はトークン（{', '.join(sorted(TOKENS))}）か #hex: {v!r}")

    for eid, e in els.items():
        check_props(eid, {k: v for k, v in e.items() if k not in COMMON | FROZEN_IN_STEPS}, eid)

    for i, st in enumerate(spec["steps"]):
        where = f"steps[{i}] (step {i + 1})"
        for k in st.keys() - {"caption", "set", "len"}:
            E(f"{where}: 未知のキー '{k}'")
        if "len" in st and not (isinstance(st["len"], (int, float)) and st["len"] > 0):
            E(f"{where}.len: 正の数")
        for eid, props in (st.get("set") or {}).items():
            if eid not in els:
                E(f"{where}.set: 存在しない要素 '{eid}'")
            elif not isinstance(props, dict):
                E(f"{where}.set.{eid}: object であること")
            else:
                check_props(eid, props, f"{where}.set.{eid}")

    # references and per-step range checks on the carried-forward state
    for eid, e in els.items():
        t = e["type"]
        if t == "pointer" and els.get(e.get("array"), {}).get("type") != "array":
            E(f"{eid}.array: array 要素 '{e.get('array')}' が無い")
        if t in ("curve", "dot") and els.get(e.get("plot"), {}).get("type") != "plot":
            E(f"{eid}.plot: plot 要素 '{e.get('plot')}' が無い")
        if t == "arrow":
            for k in ("from", "to"):
                if k in e:
                    ref, _, idx = str(e[k]).partition(":")
                    if ref not in els:
                        E(f"{eid}.{k}: 存在しない要素 '{ref}'")
                    elif idx and els[ref]["type"] != "array":
                        E(f"{eid}.{k}: ':index' は array 要素にだけ使える")
    if errs:
        return errs
    cur = {eid: dict(e) for eid, e in els.items()}
    for i, st in enumerate(spec["steps"]):
        for eid, props in (st.get("set") or {}).items():
            for k, v in props.items():
                if isinstance(v, dict) and isinstance(cur[eid].get(k), dict):
                    cur[eid][k] = {**cur[eid][k], **v}
                else:
                    cur[eid][k] = v
        s = f"step {i + 1}"
        for eid, c in cur.items():
            t = c["type"]
            if t == "code" and not (0 <= c.get("hl", 0) <= len(c["lines"])):
                E(f"{s}: {eid}.hl={c.get('hl')} が行数 {len(c['lines'])} の範囲外（0 で非表示）")
            if t == "array":
                n = len(c["values"])
                if n != len(els[eid]["values"]):
                    E(f"{s}: {eid}.values の長さは変えられない（{len(els[eid]['values'])} → {n}）")
                if "order" in c and sorted(c["order"]) != list(range(n)):
                    E(f"{s}: {eid}.order は 0..{n - 1} の並べ替えであること")
            if t == "pointer":
                n = len(cur[c["array"]]["values"])
                if not (-1 <= c["index"] <= n):
                    E(f"{s}: {eid}.index={c['index']} が配列の範囲外")
            if t == "plot":
                for k in ("xr", "yr"):
                    r = c[k]
                    if not (isinstance(r, list) and len(r) == 2 and r[0] < r[1]):
                        E(f"{s}: {eid}.{k} は [min, max]（min < max）")
    return errs


def find_chrome():
    cands = [os.environ.get("VIZ_CHROME"),
             "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
             "/Applications/Chromium.app/Contents/MacOS/Chromium"]
    cands += [shutil.which(n) for n in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable")]
    return next((c for c in cands if c and os.path.exists(c)), None)


def shoot(out, steps):
    chrome = find_chrome()
    if not chrome:
        print("viz: Chrome が見つからないので --shot を飛ばした（VIZ_CHROME で指定可）", file=sys.stderr)
        return
    with tempfile.TemporaryDirectory() as prof:
        for s in steps:
            png = out.with_name(f"{out.stem}-s{s}.png")
            subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={prof}",
                            "--window-size=1280,860", "--virtual-time-budget=1500", f"--screenshot={png}",
                            f"{out.resolve().as_uri()}#s={s}&shot"], check=False, capture_output=True, timeout=60)
            print(png if png.exists() else f"viz: screenshot 失敗 s={s}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("-o", "--out")
    ap.add_argument("--open", action="store_true")
    ap.add_argument("--shot", help="comma-separated 1-based step positions, e.g. 1,2.5,4")
    ap.add_argument("--ascii", action="store_true", help="print each step as a text frame (terminal)")
    ap.add_argument("--cols", type=int, default=100, help="--ascii の横幅（既定 100）")
    a = ap.parse_args()

    src = Path(a.spec).expanduser()
    try:
        spec = json.loads(src.read_text())
    except json.JSONDecodeError as e:
        sys.exit(f"viz: JSON が壊れている: {e}")
    errs = validate(spec)
    if errs:
        sys.exit("viz: spec にエラー:\n  " + "\n  ".join(errs))

    if a.ascii:
        sys.path.insert(0, str(HERE))
        import ascii as viz_ascii
        print(viz_ascii.render(spec, cols=a.cols))
        return

    page = (HERE / "template.html").read_text()
    blob = json.dumps(spec, ensure_ascii=False).replace("</", "<\\/")
    page = page.replace("__TITLE__", html.escape(spec.get("title") or "viz"), 1)
    page = page.replace("/*__SPEC__*/null", blob, 1)
    out = Path(a.out).expanduser() if a.out else src.with_suffix(".html")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    print(out)
    if a.shot:
        shoot(out, [s.strip() for s in a.shot.split(",") if s.strip()])
    if a.open:
        subprocess.run(["open" if sys.platform == "darwin" else "xdg-open", str(out)], check=False)


if __name__ == "__main__":
    main()
