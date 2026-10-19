"""config — 調整つまみを1か所に集める。コードを触らずに絞り込みを変えたいときはここだけ直す。"""
import os

# 出力先。env JOB_WATCH_DIR で差し替え可（テスト用）。
BASE_DIR = os.path.expanduser(os.environ.get("JOB_WATCH_DIR", "~/Store/30_Work/job-hunt-2027/job-watch"))

SIMPLIFY = [
    ("newgrad", "https://raw.githubusercontent.com/SimplifyJobs/New-Grad-Positions/dev/.github/scripts/listings.json"),
    ("intern", "https://raw.githubusercontent.com/SimplifyJobs/Summer2027-Internships/dev/.github/scripts/listings.json"),
]

ORACLE_BASE = "https://eeho.fa.us2.oraclecloud.com"
ORACLE_SITE = "CX_45001"
ORACLE_KEYWORDS = ["data center technician", "new grad", "university", "intern", "IC1", "Software Developer 1"]
ORACLE_LIMIT = 50
# Oracle の検索は大雑把なので、題名がこれに当たるものだけ拾う（entry-level の目印）。
ORACLE_TITLE_OK = r"intern|co-?op|new (college )?grad|undergrad|university|graduate|\bIC1\b|(developer|engineer|analyst|associate)\s*(1|I)\b|data center|technician"
# 上の題名に加えて技術職らしさも要る（"Operations Analyst Intern - OVIP" 等の事務系を落とす）。
ORACLE_TECH_RE = r"software|developer|engineer|technician|data center|cloud|\bOCI\b|infra|security|network|systems?\b|devops|\bIC1\b"
# Oracle の Senior はふつう除外だが、これは entry-level なので通す（調査 2026-10-14）。
TITLE_REJECT_EXCEPT = ["senior data center support services technician"]

# Simplify のカテゴリ（これ以外は落とす）。
CATEGORIES = {"Software", "Software Engineering", "Hardware", "AI/ML/Data", "Data Science, AI & Machine Learning"}
# Hardware／AI/ML/Data は母数が大きく機械・ML 職が混ざるので、題名が興味領域に当たるものだけ通す。
BOOST_REQUIRED_CATEGORIES = {"Hardware", "AI/ML/Data", "Data Science, AI & Machine Learning"}
BOOST_RE = r"infra|network|security|cloud|systems?\b|\bsre\b|reliab|devops|platform|data ?center|linux|firmware|embedded|kernel|automation|\bit\b|support engineer|solutions? engineer"
TITLE_REJECT_RE = r"\bsenior\b|\bsr\.?\b|\bstaff\b|\bprincipal\b|manager|director|\blead\b|head of|\bvp\b|ph\.?d"

# 場所の優先度。tier1=オースティン周辺 > tier2=テキサス > tier3=リモート(US)。
TIER1_CITIES = ["austin", "round rock", "san marcos", "georgetown", "pflugerville", "kyle", "buda", "taylor", "cedar park", "san antonio"]

MAX_AGE_DAYS = 150     # date_posted がこれより古い掲載は無視（放置された掲載を拾わない）
MAX_FETCHES = 60       # 1回の実行で本文を取りに行く上限。超えた分は seen にせず翌日に回す
MAX_FETCHES_BACKFILL = 400  # state が空の初回だけ（全件を一度に報告するため）
FETCH_TIMEOUT = 15
USER_AGENT = "job-watch/1.0 (personal job search; polite, low volume)"
BACKLOG_SIZE = "15m"
