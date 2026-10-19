"""sources — 求人の取得役。各関数は候補 dict のリストを返し、失敗は呼び出し側（cli）が source 単位で握る。

候補 dict: key, source, kind(newgrad|intern), company, title, location, tier, url, boost, sponsorship, oracle_id
"""
import re
import time
import urllib.parse
from . import config as C, filters as F, net


def simplify(kind, url, now_epoch=None, stats=None):
    now_epoch = now_epoch or time.time()
    data = net.http_json(url, timeout=60)
    out = []
    for r in data:
        if stats is not None:
            stats["scanned"] += 1
        hit = F.simplify_ok(r, kind, now_epoch)
        if not hit:
            continue
        tier, loc, b = hit
        out.append({"key": "simplify:" + str(r["id"]), "source": "Simplify", "kind": kind, "company": r.get("company_name", "?"),
                    "title": r.get("title", "?"), "location": loc, "tier": tier, "url": r.get("url", ""), "boost": b,
                    "sponsorship": r.get("sponsorship")})
    return out


def oracle(now_date, stats=None):
    seen, out = set(), []
    for kw in C.ORACLE_KEYWORDS:
        q = ("%s/hcmRestApi/resources/latest/recruitingCEJobRequisitions?onlyData=true&expand=requisitionList.secondaryLocations"
             "&finder=findReqs;siteNumber=%s,keyword=%s,limit=%d" % (C.ORACLE_BASE, C.ORACLE_SITE, urllib.parse.quote(kw), C.ORACLE_LIMIT))
        d = net.http_json(q)
        for item in d.get("items", []):
            for r in item.get("requisitionList", []):
                rid = str(r.get("Id"))
                if rid in seen:
                    continue
                seen.add(rid)
                if stats is not None:
                    stats["scanned"] += 1
                title = r.get("Title", "")
                if not (re.search(C.ORACLE_TITLE_OK, title, re.I) and re.search(C.ORACLE_TECH_RE, title, re.I)) or not F.title_ok(title):
                    continue
                posted = r.get("PostedDate") or ""
                if posted and (now_date - _date(posted)).days > C.MAX_AGE_DAYS:
                    continue
                locs = [r.get("PrimaryLocation", "")] + [s.get("Name", "") for s in r.get("secondaryLocations") or []]
                tier, loc = F.best_location(locs)
                if tier is None:
                    continue
                kind = "intern" if re.search(r"intern|co-?op", title, re.I) else "newgrad"
                out.append({"key": "oracle:" + rid, "source": "Oracle", "kind": kind, "company": "Oracle", "title": title, "location": loc,
                            "tier": tier, "url": "%s/hcmUI/CandidateExperience/en/sites/%s/job/%s" % (C.ORACLE_BASE, C.ORACLE_SITE, rid),
                            "boost": F.boost(title), "sponsorship": None, "oracle_id": rid})
    return out


def _date(s):
    import datetime as dt
    return dt.datetime.strptime(s[:10], "%Y-%m-%d").date()
