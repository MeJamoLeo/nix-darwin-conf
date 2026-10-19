"""classify — 求人本文を就労資格の観点で分類する（正規表現のみ・ネットワークなし）。

クラス:
  EXCLUDE      応募しても無駄（市民権・クリアランス・ITAR・OPT/CPT/F-1 を明示排除・「now or in the future」で sponsor 不可）
  F1_OK        F-1／CPT／OPT を歓迎、または sponsorship ありと明記
  NO_H1B_ONLY  「H-1B 不可」「sponsor しない」だけで将来句が無い（CPT/OPT は別扱いの余地＝曖昧）
  SILENT       記載なし
  UNKNOWN      本文が取れなかった（呼び出し側が付ける）
★ F1_OK を先に見る。Cloudflare は「now or in the future require sponsorship … if you hold F1 status, select YES」
  と書くので、将来句だけで EXCLUDE すると誤爆する。ただし市民権・クリアランス等の hard 排除は F1_OK でも勝つ。
"""
import re

TERMS = r"\b(?:OPT|CPT|EAD|I-?20|F-?1|STEM OPT)\b"
NEG = r"\bnot\b|\bno\b|n't|\bunable\b|\bcannot\b|\bineligible\b|\bwithout\b"
HARD = [
    (r"u\.?s\.? citizen(?:ship)?\s+(?:is\s+)?(?:required|only)|must be (?:a )?u\.?s\.? citizen|citizenship (?:is )?required|only u\.?s\.? citizens", "citizenship"),
    (r"security clearance|secret clearance|ts/sci|top secret|active clearance", "clearance"),
    (r"\bITAR\b|\bu\.?s\.? persons?\b|export[- ]control(?:led)? (?:regulations|laws)? ?(?:require|restrict)", "ITAR/US person"),
]
F1_OK_RES = [
    r"if you (?:hold|are on|have) f-?1",
    r"\bf-?1\b[^.]{0,40}(?:welcome|eligible|accepted|encouraged|supported)",
    r"\b(?:cpt|opt)\b[^.]{0,40}(?:welcome|eligible|accepted|supported|ok)",
    r"(?:welcome|eligible|accept)\w*[^.]{0,40}\b(?:cpt|opt|f-?1)\b",
    r"\b(?:cpt|opt)\b[^.]{0,30}\b(?:yes|authorized|authorised)\b",
    r"(?:visa )?sponsorship (?:is |may be )?(?:available|offered|provided)",
    r"\bwe (?:will |do |can )?(?:offer |provide )?(?:visa )?sponsor(?:ship)?\b",
]
FUTURE_RE = r"(?:now|currently)[, ]*(?:or|and)[, ]*(?:in the )?future|in the future[^.]{0,40}(?:sponsor|visa)"
SPONSOR_RE = r"sponsor|work authori[sz]ation|visa"
NO_H1B_RES = [
    r"\bno h-?1b\b",
    r"will not sponsor|unable to sponsor|cannot sponsor|can ?not sponsor|do(?:es)? not sponsor",
    r"(?:will|does|do) not (?:be )?(?:provid|offer)\w* [^.]{0,30}(?:visa|sponsor)",
    r"not (?:be )?eligible for [^.]{0,40}sponsorship",
    r"sponsorship (?:is )?not (?:available|offered|provided)",
    r"no (?:visa )?sponsorship",
]
MAX_EVIDENCE = 200


def _sentences(text):
    text = re.sub(r"\s+", " ", text or "")
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+|\s[•·▪]\s", text) if s.strip()]


def _ev(s):
    return s if len(s) <= MAX_EVIDENCE else s[: MAX_EVIDENCE - 1] + "…"


def _positive(s):
    """否定語が F1_OK 表現の直前にあれば肯定とみなさない。"""
    for pat in F1_OK_RES:
        for m in re.finditer(pat, s, re.I):
            if not re.search(NEG, s[max(0, m.start() - 25): m.start()], re.I):
                return True
    return False


def classify(text):
    """-> (cls, evidence)。text が空なら呼び出し側で UNKNOWN にする。"""
    sents = _sentences(text)
    for s in sents:
        for pat, label in HARD:
            if re.search(pat, s, re.I):
                return "EXCLUDE", _ev(s)
    for s in sents:  # F-1 系の語を含む否定文＝明示排除
        terms, neg = list(re.finditer(TERMS, s, re.I)), re.search(NEG, s, re.I)
        # 否定語が F-1 系の語より前にあるものだけ（"OPT welcome, no sponsorship needed" を誤爆させない）
        if terms and neg and neg.start() < terms[-1].start() and re.search(r"eligib|position|authori|accept|consider|work|sponsor|employ", s, re.I):
            return "EXCLUDE", _ev(s)
    for s in sents:
        if _positive(s) and (re.search(TERMS, s, re.I) or re.search(r"sponsor", s, re.I)):
            return "F1_OK", _ev(s)
    for s in sents:
        if re.search(FUTURE_RE, s, re.I) and re.search(SPONSOR_RE, s, re.I):
            return "EXCLUDE", _ev(s)
    for s in sents:
        if any(re.search(p, s, re.I) for p in NO_H1B_RES):
            return "NO_H1B_ONLY", _ev(s)
    return "SILENT", ""
