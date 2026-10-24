#!/usr/bin/env python3
"""Build printable PDFs for AtCoder problems via NoviSteps.

Reads `~/.cache/cp-dashboard/novisteps.json`, picks tasks by topic
(workbook) + grade + status, fetches the AtCoder problem HTML, converts
to LaTeX, and compiles per-problem PDFs plus a combined batch PDF.
"""

from __future__ import annotations

import argparse
import gzip
import html as html_lib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

from bs4 import BeautifulSoup

GRADES = [
    "Q10", "Q9", "Q8", "Q7", "Q6", "Q5", "Q4",
    "Q3", "Q2", "Q1",
    "D1", "D2", "D3", "D4", "D5", "D6", "D7",
]
GRADE_INDEX = {g: i for i, g in enumerate(GRADES)}

NOVISTEPS_CACHE = Path.home() / ".cache" / "cp-dashboard" / "novisteps.json"
CP_PRINT_CACHE = Path.home() / ".cache" / "cp-print"
ATCODER_CACHE = CP_PRINT_CACHE / "atcoder"
PROBLEMS_CACHE = CP_PRINT_CACHE / "problems.json"
PROBLEMS_URL = "https://kenkoooo.com/atcoder/resources/problems.json"
PROBLEMS_TTL = 7 * 86400
REQUEST_DELAY = 1.0
UA = (
    "Mozilla/5.0 (X11; Linux x86_64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)


def expand(p: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(p)))


def fetch_url(url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": UA, "Accept-Encoding": "gzip"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
        if r.headers.get("Content-Encoding") == "gzip":
            data = gzip.decompress(data)
        return data


# -------------------- NoviSteps + problems map --------------------

def load_novisteps() -> dict:
    if not NOVISTEPS_CACHE.exists():
        sys.exit(f"NoviSteps cache not found: {NOVISTEPS_CACHE}")
    return json.loads(NOVISTEPS_CACHE.read_text())


def load_problems_map(refresh: bool = False) -> dict[str, str]:
    PROBLEMS_CACHE.parent.mkdir(parents=True, exist_ok=True)
    use_cache = (
        not refresh
        and PROBLEMS_CACHE.exists()
        and (time.time() - PROBLEMS_CACHE.stat().st_mtime) < PROBLEMS_TTL
    )
    if not use_cache:
        print("[cp-print] fetching AtCoder Problems index...", file=sys.stderr)
        PROBLEMS_CACHE.write_bytes(fetch_url(PROBLEMS_URL))
    arr = json.loads(PROBLEMS_CACHE.read_text())
    return {p["id"]: p["contest_id"] for p in arr}


def match_topic(novi: dict, query: str | None) -> tuple[str, dict]:
    workbooks: dict = novi.get("workbooks", {})
    if not workbooks:
        sys.exit("no workbooks in NoviSteps cache")
    if query:
        ql = query.lower()
        hits = [
            (s, w) for s, w in workbooks.items()
            if ql in w.get("title", "").lower()
        ]
        if len(hits) == 1:
            return hits[0]
        if not hits:
            sys.exit(f"no topic matches: {query!r}")
        candidates = hits
    else:
        candidates = list(workbooks.items())

    if not shutil.which("fzf"):
        for _, w in candidates:
            print(f"  {w['title']}", file=sys.stderr)
        sys.exit("install fzf or pass a more specific --topic")

    titles = [w["title"] for _, w in candidates]
    proc = subprocess.run(
        ["fzf", "--prompt=topic> "],
        input="\n".join(titles), capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit("topic selection cancelled")
    chosen = proc.stdout.strip()
    for s, w in candidates:
        if w["title"] == chosen:
            return s, w
    sys.exit(f"topic not found after fzf: {chosen}")


def parse_grade_args(args) -> set[str]:
    for g in (args.grade, args.grade_min, args.grade_max):
        if g and g not in GRADE_INDEX:
            sys.exit(f"unknown grade: {g}")
    if args.grade:
        return {args.grade}
    lo = GRADE_INDEX[args.grade_min] if args.grade_min else 0
    hi = GRADE_INDEX[args.grade_max] if args.grade_max else len(GRADES) - 1
    if lo > hi:
        sys.exit(f"grade-min {args.grade_min} is harder than grade-max {args.grade_max}")
    return {GRADES[i] for i in range(lo, hi + 1)}


def filter_tasks(workbook: dict, grades: set[str], statuses: set[str]) -> list[dict]:
    tasks = list(workbook.get("tasks", []))
    tasks = [t for t in tasks if t["grade"] in grades and t["status"] in statuses]
    tasks.sort(key=lambda t: (GRADE_INDEX.get(t["grade"], 999), t["task_id"]))
    return tasks


# -------------------- AtCoder fetch --------------------

def atcoder_url(contest_id: str, task_id: str) -> str:
    return f"https://atcoder.jp/contests/{contest_id}/tasks/{task_id}?lang=ja"


def fetch_atcoder(contest_id: str, task_id: str, refresh: bool) -> str:
    cache = ATCODER_CACHE / f"{task_id}.html"
    if not refresh and cache.exists():
        return cache.read_text(encoding="utf-8", errors="replace")
    ATCODER_CACHE.mkdir(parents=True, exist_ok=True)
    url = atcoder_url(contest_id, task_id)
    print(f"[cp-print] fetching {url}", file=sys.stderr)
    text = fetch_url(url).decode("utf-8", errors="replace")
    cache.write_text(text, encoding="utf-8")
    time.sleep(REQUEST_DELAY)
    return text


# -------------------- HTML -> LaTeX --------------------

LATEX_SPECIAL = {
    "&": r"\&", "%": r"\%", "$": r"\$", "#": r"\#",
    "_": r"\_", "{": r"\{", "}": r"\}",
    "~": r"\textasciitilde{}", "^": r"\textasciicircum{}",
    "\\": r"\textbackslash{}",
    # Decorative glyphs neither IPAex nor DejaVu carry — typical90 titles
    # use ★ as a difficulty marker.
    "★": r"$\bigstar$", "☆": r"$\star$",
    "◆": r"$\blacklozenge$", "◇": r"$\lozenge$",
    "●": r"$\bullet$", "○": r"$\circ$",
}


def tex_escape(s: str) -> str:
    return "".join(LATEX_SPECIAL.get(c, c) for c in s)


def html_to_latex(html_str: str) -> str:
    """Pipe HTML through pandoc into LaTeX (fragment).

    AtCoder problems carry math either as ``<var>...</var>`` (older style)
    or as MathJax-style ``\\(...\\)`` / ``\\[...\\]`` literal delimiters in
    the body text. Pandoc's HTML reader doesn't recognize those delimiters
    on its own — left as-is the backslashes get escaped to literal
    ``\\textbackslash(``. Wrap them in ``<span class="math ...">`` so
    pandoc emits proper LaTeX inline/display math.
    """
    # Strip MathJax loader/config scripts only — keep the `<script type=
    # "math/tex">` markers that pandoc parses as math.
    html_str = re.sub(
        r'<script\b(?![^>]*type="math/tex)[^>]*>.*?</script>',
        "",
        html_str, flags=re.DOTALL,
    )
    # HTML entities inside math (`&lt;`, `&gt;`, `&amp;`) need to reach
    # LaTeX as their decoded form — `&` alone would be parsed as an
    # alignment tab and crash the build.
    def to_inline_math(m: re.Match) -> str:
        return f'<script type="math/tex">{html_lib.unescape(m.group(1))}</script>'

    def to_display_math(m: re.Match) -> str:
        return (
            '<script type="math/tex; mode=display">'
            + html_lib.unescape(m.group(1)) + "</script>"
        )

    # Old AtCoder pages put bare Unicode comparators inside <var>...</var>
    # (e.g. abc061: ``<var>2≦N,M≦50</var>``). Once the <var> is wrapped in a
    # math script, IPAex can't render the glyph. Replace them inline first.
    UNICODE_MATH = {
        "≤": r"\le ", "≥": r"\ge ", "≦": r"\leqq ", "≧": r"\geqq ",
        "≠": r"\ne ", "≈": r"\approx ", "≡": r"\equiv ",
        "≪": r"\ll ", "≫": r"\gg ",
    }

    def fix_var_unicode(m: re.Match) -> str:
        body = m.group(1)
        for ch, cmd in UNICODE_MATH.items():
            body = body.replace(ch, cmd)
        return f"<var>{body}</var>"

    html_str = re.sub(
        r"<var\b[^>]*>(.*?)</var>", fix_var_unicode,
        html_str, flags=re.DOTALL,
    )
    html_str = re.sub(
        r"<var\b[^>]*>(.*?)</var>", to_inline_math,
        html_str, flags=re.DOTALL,
    )
    html_str = re.sub(
        r"\\\[(.+?)\\\]", to_display_math,
        html_str, flags=re.DOTALL,
    )
    html_str = re.sub(
        r"\\\((.+?)\\\)", to_inline_math,
        html_str, flags=re.DOTALL,
    )
    # Now handle prose-level Unicode comparators (outside any math script).
    # Stash existing math scripts so nested substitutions don't corrupt them.
    stash: list[str] = []

    def hide(m: re.Match) -> str:
        stash.append(m.group(0))
        return f"\x00MATH{len(stash) - 1}\x00"

    html_str = re.sub(
        r'<script\b[^>]*type="math/tex[^"]*"[^>]*>.*?</script>',
        hide, html_str, flags=re.DOTALL,
    )
    for ch, cmd in UNICODE_MATH.items():
        html_str = html_str.replace(
            ch, f'<script type="math/tex">{cmd}</script>',
        )
    html_str = re.sub(
        r"\x00MATH(\d+)\x00",
        lambda m: stash[int(m.group(1))],
        html_str,
    )
    proc = subprocess.run(
        ["pandoc", "-f", "html", "-t", "latex", "--wrap=none"],
        input=html_str, capture_output=True, text=True, check=True,
    )
    return proc.stdout.strip()


def download_images(node, image_dir: Path) -> None:
    for img in node.find_all("img"):
        src = img.get("src") or ""
        if not src:
            continue
        if src.startswith("//"):
            url = "https:" + src
        elif src.startswith("/"):
            url = "https://atcoder.jp" + src
        else:
            url = src
        fname = re.sub(r"[^A-Za-z0-9._-]", "_", url.split("/")[-1] or "img")
        local = image_dir / fname
        if not local.exists():
            try:
                local.write_bytes(fetch_url(url))
                time.sleep(REQUEST_DELAY)
            except Exception as e:
                print(f"[cp-print] image fetch failed {url}: {e}", file=sys.stderr)
                img.decompose()
                continue
        img["src"] = str(local)
        # Drop AtCoder-supplied sizing so the preamble's \setkeys{Gin}{...}
        # clamps every figure to the column width.
        for attr in ("width", "height", "style"):
            if attr in img.attrs:
                del img[attr]


def _render_pre_with_math(pre_node) -> str:
    r"""Render a ``<pre>`` whose lines may carry MathJax (\(...\), <var>, etc.).

    Plain Verbatim is wrong here — math like ``\mathrm{query}_1`` would print
    literally. Each line is sent through ``html_to_latex`` individually so the
    existing MathJax-aware preprocessing kicks in, then the result is wrapped
    in a framed minipage that mimics the verbatim look.
    """
    raw = "".join(str(c) for c in pre_node.contents)
    lines = raw.split("\n")
    while lines and not lines[-1].strip():
        lines.pop()
    rendered: list[str] = []
    for ln in lines:
        if ln.strip() == "":
            rendered.append("~")
            continue
        rendered.append(html_to_latex(ln) or "~")
    body = " \\\\\n".join(rendered)
    return (
        "\\begin{center}"
        "\\fbox{\\begin{minipage}{0.96\\linewidth}\\ttfamily\\scriptsize\n"
        + body +
        "\n\\end{minipage}}\\end{center}"
    )


def _has_math(pre_node) -> bool:
    raw = "".join(str(c) for c in pre_node.contents)
    return bool(
        "\\(" in raw or "\\[" in raw
        or re.search(r"<var\b", raw)
        or re.search(r"\\[a-zA-Z]+", raw)
    )


def section_to_latex(section: dict, image_dir: Path) -> str:
    node = section["node"]
    heading = section["heading"]
    download_images(node, image_dir)
    is_sample = ("入力例" in heading) or ("出力例" in heading) or ("サンプル" in heading)
    if is_sample:
        parts: list[str] = []
        for child in node.find_all(["pre", "p"], recursive=False):
            if child.name == "pre":
                text = child.get_text()
                parts.append(
                    "\\begin{Verbatim}[frame=single,framesep=2pt,"
                    "fontsize=\\scriptsize,xleftmargin=0pt,xrightmargin=0pt]\n"
                    + text.rstrip()
                    + "\n\\end{Verbatim}"
                )
            else:
                parts.append(html_to_latex(str(child)))
        return "\n\n".join(parts) if parts else html_to_latex(str(node))

    # Non-sample: render children sequentially so we can intercept
    # math-bearing <pre> (input/output format specs).
    children = list(node.find_all(True, recursive=False))
    if not children:
        return html_to_latex(str(node))
    parts: list[str] = []
    for child in children:
        if child.name == "pre" and _has_math(child):
            parts.append(_render_pre_with_math(child))
        else:
            parts.append(html_to_latex(str(child)))
    return "\n\n".join(p for p in parts if p)


def parse_problem(html_text: str, task_id: str) -> dict:
    soup = BeautifulSoup(html_text, "html.parser")
    title_node = soup.select_one("span.h2") or soup.select_one("h2")
    if title_node:
        # AtCoder appends an "解説" (editorial) link inside the title node.
        for a in title_node.find_all("a"):
            a.decompose()
        title = title_node.get_text(strip=True)
    else:
        title = task_id

    ja = soup.select_one("span.lang-ja") or soup.select_one("#task-statement")
    if not ja:
        return {"title": title, "sections": []}

    sections: list[dict] = []
    parts = ja.select(".part > section")
    if not parts:
        parts = ja.select("section")
    for part in parts:
        h3 = part.find("h3")
        if not h3:
            continue
        h_title = h3.get_text(strip=True)
        h3.extract()
        sections.append({"heading": h_title, "node": part})
    if not sections:
        sections.append({"heading": "問題", "node": ja})
    return {"title": title, "sections": sections}


# -------------------- LaTeX template --------------------

LATEX_PREAMBLE = r"""\documentclass[a4paper]{article}
\usepackage[margin=10mm]{geometry}
\usepackage{fontspec}
\usepackage{xeCJK}
\usepackage{anyfontsize}
\usepackage{amsmath}
\usepackage{amssymb}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{xcolor}
\usepackage{tikz}
\usepackage{eso-pic}
\usepackage{enumitem}
\usepackage{multicol}
\usepackage{fancyvrb}
\setlength{\columnsep}{5mm}
\setlength{\columnseprule}{0pt}
% IPAex (static TrueType) + DejaVu chosen because xelatex/xdvipdfmx can't
% embed the variable-axis Noto OTC that NixOS ships by default.
\setCJKmainfont{IPAexMincho}
\setCJKsansfont{IPAexGothic}
\setCJKmonofont{IPAexGothic}
\setmainfont{DejaVu Serif}
\setsansfont{DejaVu Sans}
\setmonofont{DejaVu Sans Mono}
\setlength{\parindent}{0pt}
\setlength{\parskip}{2pt}
\pagestyle{empty}
\hypersetup{colorlinks=true,urlcolor=blue!50!black}

% pandoc emits \tightlist; define it so xelatex doesn't choke.
\providecommand{\tightlist}{%
  \setlength{\itemsep}{0pt}\setlength{\parskip}{0pt}}

% MathJax extensions used by AtCoder statements but absent from amsmath.
\providecommand{\lt}{<}
\providecommand{\gt}{>}

% Clamp figures to column width so a tall AtCoder diagram doesn't bleed out
% of its 3-column slot.
\setkeys{Gin}{width=\linewidth, keepaspectratio}

% Light 5mm grid covering the writable area on every page.
\AddToShipoutPictureBG{%
  \begin{tikzpicture}[remember picture,overlay]
    \draw[gray!20,line width=0.1pt,step=5mm]
      ([shift={(10mm,10mm)}]current page.south west) grid
      ([shift={(-10mm,-10mm)}]current page.north east);
  \end{tikzpicture}%
}

\begin{document}
\fontsize{8pt}{10pt}\selectfont
"""

LATEX_POSTAMBLE = "\n\\end{document}\n"


def build_problem_tex(
    task: dict, contest_id: str, topic: str, parsed: dict, image_dir: Path,
) -> str:
    task_id = task["task_id"]
    grade = task["grade"]
    url = atcoder_url(contest_id, task_id)
    header_parts = [
        r"\noindent\begin{minipage}{\textwidth}",
        f"\\textbf{{\\large {tex_escape(task_id)}}}\\quad "
        f"[\\textbf{{{grade}}}]\\quad "
        f"\\textsf{{{tex_escape(topic)}}}\\\\",
        f"\\href{{{url}}}{{\\small\\ttfamily {tex_escape(url)}}}",
        r"\end{minipage}\par\vspace{1mm}\hrule\vspace{2mm}",
    ]
    # Split sections: non-sample go left; sample I/O pairs go middle/right.
    left_sections: list[dict] = []
    sample_sections: list[dict] = []
    for sec in parsed["sections"]:
        h = sec["heading"]
        if ("入力例" in h) or ("出力例" in h) or ("サンプル" in h):
            sample_sections.append(sec)
        else:
            left_sections.append(sec)

    sample_pairs: list[list[dict]] = []
    i = 0
    while i < len(sample_sections):
        pair = [sample_sections[i]]
        if (
            i + 1 < len(sample_sections)
            and "入力例" in sample_sections[i]["heading"]
            and "出力例" in sample_sections[i + 1]["heading"]
        ):
            pair.append(sample_sections[i + 1])
            i += 2
        else:
            i += 1
        sample_pairs.append(pair)

    def render(sections_iter) -> str:
        out: list[str] = []
        for sec in sections_iter:
            # \nopagebreak so multicols can't strand the heading at the
            # bottom of a column with its body in the next column.
            out.append(
                f"\\par\\smallskip\\textbf{{{tex_escape(sec['heading'])}}}"
                f"\\nopagebreak\\par\\nopagebreak"
            )
            out.append(section_to_latex(sec, image_dir))
        return "\n".join(out)

    title_tex = (
        f"\\textbf{{\\large {tex_escape(parsed['title'])}}}\\par\n"
        if parsed.get("title") else ""
    )

    # multicols flows naturally across columns and breaks at the page
    # bottom — fixed minipages can't, so long problems were burning a blank
    # cover page (header on p1, atomic 3-col block forced to p2).
    ordered = [s for s in left_sections if s["heading"] == "問題文"]
    ordered += [s for s in left_sections if s["heading"] != "問題文"]
    ordered += [s for pair in sample_pairs for s in pair]
    body = title_tex + render(ordered)

    cols = (
        r"\begin{multicols}{3}" + "\n"
        + body + "\n"
        + r"\end{multicols}"
    )

    body_parts: list[str] = ["\n".join(header_parts), cols]
    return LATEX_PREAMBLE + "\n\n".join(body_parts) + LATEX_POSTAMBLE


# -------------------- xelatex / concat --------------------

def compile_pdf(tex: str, out_pdf: Path) -> bool:
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        src = tdp / "problem.tex"
        src.write_text(tex, encoding="utf-8")
        rc = 0
        for _ in range(2):
            proc = subprocess.run(
                ["xelatex", "-interaction=nonstopmode", "-halt-on-error",
                 "-output-directory", td, str(src)],
                capture_output=True, text=True,
            )
            rc = proc.returncode
        pdf = tdp / "problem.pdf"
        # xelatex sometimes leaves a header-only PDF after an error; require both
        # a successful exit and a non-trivial output file.
        if rc != 0 or not pdf.exists() or pdf.stat().st_size < 1024:
            print(f"[cp-print] xelatex failed for {out_pdf.name} (rc={rc})",
                  file=sys.stderr)
            log = tdp / "problem.log"
            if log.exists():
                tail = "\n".join(log.read_text(errors="replace").splitlines()[-25:])
                print(tail, file=sys.stderr)
            return False
        out_pdf.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(pdf, out_pdf)
    return True


def concat_pdfs(inputs: list[Path], output: Path) -> None:
    if not inputs:
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    if len(inputs) == 1:
        shutil.copy(inputs[0], output)
        return
    if shutil.which("pdfunite"):
        subprocess.run(
            ["pdfunite", *[str(p) for p in inputs], str(output)], check=True,
        )
    elif shutil.which("qpdf"):
        subprocess.run(
            ["qpdf", "--empty", "--pages",
             *[str(p) for p in inputs], "--", str(output)], check=True,
        )
    else:
        sys.exit("need pdfunite or qpdf to concatenate PDFs")


# -------------------- Main --------------------

def safe_dirname(s: str) -> str:
    return re.sub(r"[/\x00]", "_", s).strip()


def filter_tag(args) -> str:
    if args.grade:
        return args.grade
    if args.grade_max and args.grade_min:
        return f"{args.grade_min}-{args.grade_max}"
    if args.grade_max:
        return f"le{args.grade_max}"
    if args.grade_min:
        return f"ge{args.grade_min}"
    return "all"


def main() -> None:
    p = argparse.ArgumentParser(description="Build printable AtCoder problem PDFs")
    p.add_argument("--topic", help="fuzzy substring against workbook title (default: fzf)")
    p.add_argument("--grade", help="single grade, e.g., 4Q")
    p.add_argument("--grade-max", dest="grade_max",
                   help="upper bound: '4Q' means 4Q and easier")
    p.add_argument("--grade-min", dest="grade_min", help="lower bound on difficulty")
    p.add_argument("--status", default="ns",
                   help="CSV from {ns,wa,ac,ac_with_editorial}")
    p.add_argument("--output-dir",
                   default=os.environ.get(
                       "CP_PRINT_OUTPUT_DIR",
                       str(Path.home() / "workspace" / "novisteps_prints"),
                   ))
    p.add_argument("--force", action="store_true",
                   help="rebuild per-problem PDFs even when cached")
    p.add_argument("--refresh", action="store_true",
                   help="refresh AtCoder HTML cache and problems map")
    args = p.parse_args()

    out_root = expand(args.output_dir)
    out_root.mkdir(parents=True, exist_ok=True)

    novi = load_novisteps()
    if novi.get("cookie_expired"):
        print("[cp-print] warning: NoviSteps cookie expired; data may be stale",
              file=sys.stderr)

    slug, workbook = match_topic(novi, args.topic)
    topic = workbook["title"]
    print(f"[cp-print] topic: {topic} (slug={slug})", file=sys.stderr)

    grades = parse_grade_args(args)
    statuses = {s.strip() for s in args.status.split(",") if s.strip()}
    tasks = filter_tasks(workbook, grades, statuses)
    if not tasks:
        sys.exit("no tasks match filters")
    print(f"[cp-print] {len(tasks)} task(s) match", file=sys.stderr)

    problems_map = load_problems_map(refresh=args.refresh)

    topic_dir = out_root / safe_dirname(topic)
    image_root = out_root / "_images" / safe_dirname(topic)
    image_root.mkdir(parents=True, exist_ok=True)

    ac_ids = {
        t["task_id"] for t in workbook.get("tasks", [])
        if t["status"] in ("ac", "ac_with_editorial")
    }
    if topic_dir.exists():
        for pdf in topic_dir.rglob("*.pdf"):
            if pdf.stem in ac_ids:
                pdf.unlink()
                print(f"[cp-print] pruned AC'd {pdf.name}", file=sys.stderr)

    per_problem_pdfs: list[Path] = []
    built = skipped = failed = 0
    for task in tasks:
        task_id = task["task_id"]
        grade = task["grade"]
        contest_id = problems_map.get(task_id)
        if not contest_id:
            print(f"[cp-print] no contest mapping for {task_id}, skip",
                  file=sys.stderr)
            failed += 1
            continue
        pdf_path = topic_dir / grade / f"{task_id}.pdf"
        if pdf_path.exists() and not args.force:
            per_problem_pdfs.append(pdf_path)
            skipped += 1
            continue
        try:
            html_text = fetch_atcoder(contest_id, task_id, args.refresh)
        except Exception as e:
            print(f"[cp-print] fetch failed {task_id}: {e}", file=sys.stderr)
            failed += 1
            continue
        parsed = parse_problem(html_text, task_id)
        tex = build_problem_tex(task, contest_id, topic, parsed, image_root)
        if compile_pdf(tex, pdf_path):
            per_problem_pdfs.append(pdf_path)
            built += 1
        else:
            failed += 1

    per_problem_pdfs.sort(key=lambda p: (
        GRADE_INDEX.get(p.parent.name, 999), p.stem,
    ))

    safe_topic = safe_dirname(topic).replace(" ", "_")
    combined_name = f"{safe_topic}_{filter_tag(args)}_{datetime.now():%Y-%m-%d}.pdf"
    combined = out_root / "_batches" / combined_name
    if per_problem_pdfs:
        concat_pdfs(per_problem_pdfs, combined)

    print(
        f"[cp-print] built={built}, skipped={skipped}, failed={failed}\n"
        f"[cp-print] per-problem: {topic_dir}\n"
        f"[cp-print] combined:    {combined}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
