"""filters — 場所の tier 付けと、題名・カテゴリ・学位・sponsorship での足切り。"""
import re
from . import config as C


def loc_tier(loc):
    """1=オースティン周辺 2=テキサス 3=リモート(US) None=対象外（非US含む）。"""
    s = (loc or "").strip().lower()
    if not s:
        return None
    if re.search(r"\b(" + "|".join(C.TIER1_CITIES) + r")\b,?\s*(tx|texas)\b", s):
        return 1
    if re.search(r",\s*tx\b|\btexas\b", s) and "canada" not in s:
        return 2
    if s.startswith("remote"):
        return 3 if re.search(r"usa|\bus\b|united states|^remote$", s) else None
    if s == "united states":
        return 3
    return None


def best_location(locs):
    """複数拠点から最良 tier を選ぶ -> (tier, 表示用の場所文字列)。"""
    ranked = sorted(((loc_tier(l), l) for l in locs or []), key=lambda t: (t[0] is None, t[0] or 9))
    ranked = [r for r in ranked if r[0] is not None]
    if not ranked:
        return None, ""
    t = ranked[0][0]
    return t, "; ".join(l for tt, l in ranked if tt == t)[:80]


def title_ok(title):
    t = (title or "").lower()
    if any(x in t for x in C.TITLE_REJECT_EXCEPT):
        return True
    return not re.search(C.TITLE_REJECT_RE, t, re.I)


def boost(title):
    return bool(re.search(C.BOOST_RE, title or "", re.I))


def degree_ok(degrees):
    return not degrees or "Bachelor's" in degrees


def simplify_ok(rec, kind, now_epoch):
    """Simplify の1件が残るか。-> 残るなら (tier, loc, boost)、落とすなら None。"""
    if not (rec.get("active") and rec.get("is_visible")):
        return None
    if now_epoch - (rec.get("date_posted") or 0) > C.MAX_AGE_DAYS * 86400:
        return None
    if rec.get("category") not in C.CATEGORIES or not degree_ok(rec.get("degrees")) or not title_ok(rec.get("title")):
        return None
    sp = rec.get("sponsorship")
    if sp == "U.S. Citizenship is Required" or (kind == "newgrad" and sp == "Does Not Offer Sponsorship"):
        return None
    tier, loc = best_location(rec.get("locations"))
    if tier is None:
        return None
    b = boost(rec.get("title"))
    if rec.get("category") in C.BOOST_REQUIRED_CATEGORIES and not b:
        return None
    return tier, loc, b
