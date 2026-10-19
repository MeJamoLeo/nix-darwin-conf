"""authcheck — 候補の本文を安く取って classify に渡す。取れなければ UNKNOWN。

ATS ごとの API（Greenhouse／Lever／Ashby）があればそれを使い、無ければ素の GET＋HTML 除去。
JS 描画の ATS（Workday 等）は素の GET だと本文が空なので、短すぎる結果は UNKNOWN 扱い。
"""
import html
import re
import urllib.parse
from . import config as C, net
from .classify import classify

_ashby_cache = {}
MIN_PLAIN_CHARS = 500


def strip_html(s):
    s = html.unescape(s or "")
    s = re.sub(r"(?is)<(script|style).*?</\1>", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</p>|</li>|</div>|</h\d>", ". ", s)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    return re.sub(r"(?:\s*\.){2,}", ".", s)  # タグ置換の ". " が元の句点と重なる分を畳む


def _greenhouse(url):
    m = re.search(r"greenhouse\.io/(?:embed/job_app\?for=)?([^/?&]+)/jobs/(\d+)", url) or None
    if not m:
        return None
    d = net.http_json("https://boards-api.greenhouse.io/v1/boards/%s/jobs/%s?content=true&questions=true" % m.groups())
    parts = [d.get("content", "")]
    for q in d.get("questions") or []:
        parts += [q.get("label", ""), q.get("description") or ""]
    return strip_html(" . ".join(parts))


def _lever(url):
    m = re.search(r"jobs\.lever\.co/([^/]+)/([0-9a-f-]{36})", url)
    if not m:
        return None
    d = net.http_json("https://api.lever.co/v0/postings/%s/%s" % m.groups())
    parts = [d.get("descriptionPlain", ""), d.get("additionalPlain", "")]
    for l in d.get("lists") or []:
        parts += [l.get("text", ""), strip_html(l.get("content", ""))]
    return " . ".join(parts)


def _ashby(url):
    m = re.search(r"jobs\.ashbyhq\.com/([^/]+)/([0-9a-f-]{36})", url)
    if not m:
        return None
    org, jid = m.groups()
    if org not in _ashby_cache:
        _ashby_cache[org] = net.http_json("https://api.ashbyhq.com/posting-api/job-board/%s" % urllib.parse.quote(org)).get("jobs", [])
    for j in _ashby_cache[org]:
        if j.get("id") == jid or str(j.get("jobUrl", "")).rstrip("/").endswith(jid):
            return j.get("descriptionPlain") or strip_html(j.get("descriptionHtml", ""))
    return None


def _oracle(cand):
    q = "%s/hcmRestApi/resources/latest/recruitingCEJobRequisitionDetails?onlyData=true&finder=ById;Id=%%22%s%%22,siteNumber=%s" % (
        C.ORACLE_BASE, cand["oracle_id"], C.ORACLE_SITE)
    items = net.http_json(q).get("items") or []
    if not items:
        return None
    return strip_html(" . ".join(str(v) for k, v in items[0].items() if isinstance(v, str) and len(v) > 40 and ("Str" in k or "Desc" in k or "Qual" in k)))


def fetch_text(cand):
    """-> テキスト or None（取れない）。例外は呼び出し側で握る。"""
    if cand.get("oracle_id"):
        return _oracle(cand)
    url = cand["url"]
    for fn in (_greenhouse, _lever, _ashby):
        t = fn(url)
        if t:
            return t
    t = strip_html(net.http_get(url))
    return t if len(t) >= MIN_PLAIN_CHARS else None


def check(cand):
    """-> (cls, evidence)。Simplify の sponsorship 欄は本文が沈黙のときの補助情報として使う。"""
    try:
        text = fetch_text(cand)
    except Exception as e:  # 1件の失敗で全体を止めない
        text, err = None, type(e).__name__
    else:
        err = "本文取得不可"
    if not text:
        return _from_simplify(cand, "UNKNOWN", err)
    cls, ev = classify(text)
    if cls == "SILENT":
        return _from_simplify(cand, cls, "")
    return cls, ev


def _from_simplify(cand, cls, ev):
    sp = cand.get("sponsorship")
    if sp == "Does Not Offer Sponsorship":
        return "NO_H1B_ONLY", "Simplify: Does Not Offer Sponsorship（intern は CPT 可の余地あり）"
    if sp == "Offers Sponsorship":
        return "F1_OK", "Simplify: Offers Sponsorship"
    return cls, ev
