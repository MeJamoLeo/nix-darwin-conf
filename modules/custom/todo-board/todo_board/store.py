"""store — パス・base ディレクトリ・env・原子的書き込み・状態／ステータスファイル・除外／別名設定。

依存の最下層（他の todo_board モジュールを import しない）。

ファイル:
  <base>/YYYY/YYYYMMDD-todo.md  日次。`# Today M/D` と `## If time allows` と末尾の状態フッタだけ。
  <base>/backlog.md             倉庫。`# Canvas`（機械管理）/ `# Dated` / `# Someday` / `# Expired`。
  <base>/.status.json           Canvas／メール取得の最終成功・直近エラー。
  <base>/.state.json            手で [x] にした行の記憶（done_ids／checked_ids。Canvas／digest から消えたら忘れる）。
  <base>/.blocks.json           blocks が分類済みのブロック（日付:セッション:区間 → 紐づけた行のキー）。0600。
  <base>/.cache/lock_at.json    過去締切項目の lock_at（24h キャッシュ）。
  <base>/courses.json           任意。{"context_name の部分文字列": "CS4355"} の別名表（コード内の既定に上書き）。
  <base>/exclude.json           任意。同期しない科目コードの配列。
  base 既定 ~/Store/30_Work/todo、env TODO_BOARD_DIR で上書き（テストはここを一時ディレクトリにする）。
"""
import datetime as dt
import json
import os
import re
import tempfile


DAILY = re.compile(r"^(\d{4})(\d{2})(\d{2})-todo\.md$")
# 実データ（planner の context_name）から。コード（CS3360 等）が名前に入っていればそちらを優先する
DEFAULT_ALIASES = {"Algorithms and Analy": "CS4355"}


def base_dir():
    return os.environ.get("TODO_BOARD_DIR") or os.path.expanduser("~/Store/30_Work/todo")


def day_path(d):
    return os.path.join(base_dir(), f"{d.year:04d}", f"{d:%Y%m%d}-todo.md")


def backlog_path():
    return os.path.join(base_dir(), "backlog.md")


def status_path():
    return os.path.join(base_dir(), ".status.json")


def state_path():
    return os.path.join(base_dir(), ".state.json")


def blocks_path():
    return os.path.join(base_dir(), ".blocks.json")


ROLL_HOUR = 6  # 日次ファイルを確定する時刻（launchd の roll）


def current_day(now):
    """いま機械が書く日次ファイルの日付。

    06:00 前に今日のファイルがまだ無ければ前日のもの（夜更かしの作業は前日の続き。06:00 の roll が
    今日のファイルを作るまで、前日のファイルが「いまの」ファイル）。今日のファイルがあればそちら。
    """
    today = now.date()
    if now.hour < ROLL_HOUR and not os.path.exists(day_path(today)):
        return today - dt.timedelta(days=1)
    return today


def lock_cache_path():
    return os.path.join(base_dir(), ".cache", "lock_at.json")


def courses_path():
    return os.path.join(base_dir(), "courses.json")


def exclude_path():
    return os.path.join(base_dir(), "exclude.json")


def load_excluded():
    """exclude.json（任意）＝ 同期しない科目コードの配列（例 ["ENG3303"]）。

    履修を中止した科目（2026-10-02 本人が ENG3303 を drop）の課題やメールが、毎時の同期で
    倉庫に戻ってこないようにする。比較はドット・空白を除いた大文字。
    """
    try:
        with open(exclude_path(), encoding="utf-8") as fh:
            v = json.load(fh)
        return {re.sub(r"[.\s]", "", str(x)).upper() for x in v} if isinstance(v, list) else set()
    except (OSError, ValueError):
        return set()


def is_excluded_text(text, excluded):
    t = re.sub(r"[.\s]", "", str(text or "")).upper()
    return any(code in t for code in excluded)


def atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".todo-")  # mkstemp は 0600
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def read_raw(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.read()


def write_if_changed(path, text):
    """冪等性のため、同一内容なら書かない（mtime も動かさない）。"""
    if os.path.exists(path) and read_raw(path) == text:
        return False
    atomic_write(path, text)
    return True


def find_prev(d):
    """d より前で最も新しい日次ファイル。数日空くのは普通なので全走査する。"""
    best = None
    base = base_dir()
    if not os.path.isdir(base):
        return None
    for y in os.listdir(base):
        yd = os.path.join(base, y)
        if not (y.isdigit() and os.path.isdir(yd)):
            continue
        for f in os.listdir(yd):
            m = DAILY.match(f)
            if not m:
                continue
            fd = dt.date(int(m[1]), int(m[2]), int(m[3]))
            if fd < d and (best is None or fd > best):
                best = fd
    return best


def load_status():
    try:
        with open(status_path(), encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_status(ok, err, now):
    st = load_status()
    c = st.get("canvas") or {}
    if ok:
        c["ok_at"] = now.strftime("%Y-%m-%dT%H:%M")
        c["error"] = None
    else:
        c["error"] = err
        c["error_at"] = now.strftime("%Y-%m-%dT%H:%M")
        c.setdefault("ok_at", None)
    st["canvas"] = c
    write_if_changed(status_path(), json.dumps(st, ensure_ascii=False, indent=2) + "\n")


def save_mail_status(info):
    st = load_status()
    st["mail"] = info
    write_if_changed(status_path(), json.dumps(st, ensure_ascii=False, indent=2) + "\n")


def save_status_key(key, info):
    """.status.json の1キー（calendar／blocks など）だけを更新する。"""
    st = load_status()
    if st.get(key) == info:
        return
    st[key] = info
    write_if_changed(status_path(), json.dumps(st, ensure_ascii=False, indent=2) + "\n")


def load_state():
    try:
        with open(state_path(), encoding="utf-8") as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        st = {}
    if not isinstance(st, dict):
        st = {}
    for k in ("done_ids", "checked_ids", "done_seen"):
        if not isinstance(st.get(k), dict):
            st[k] = {}
    return st


def save_state(st):
    write_if_changed(state_path(), json.dumps(st, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def prune_state(prefixes, alive):
    """Canvas／digest がもう返さない項目の記憶を忘れる。prefixes の種類だけが対象。"""
    st = load_state()
    changed = False
    for bucket in ("done_ids", "checked_ids", "done_seen"):
        for k in list(st[bucket]):
            if k[0] in prefixes and k not in alive:
                del st[bucket][k]
                changed = True
    if changed:
        save_state(st)


def load_aliases():
    """courses.json（任意）→ コード内の既定の順。キーは context_name の部分文字列（大小無視）。"""
    out = {}
    try:
        with open(courses_path(), encoding="utf-8") as fh:
            cfg = json.load(fh)
        if isinstance(cfg, dict):
            out.update({str(k): str(v) for k, v in cfg.items() if k and v})
    except (OSError, ValueError):
        pass
    for k, v in DEFAULT_ALIASES.items():
        out.setdefault(k, v)
    return out


def latest_day_file(today):
    """今日以前で最新の日次ファイル（無ければ None）。show が今日の分が無いときに使う。"""
    best = None
    root = base_dir()
    if not os.path.isdir(root):
        return None
    for y in os.listdir(root):
        yd = os.path.join(root, y)
        if not (y.isdigit() and os.path.isdir(yd)):
            continue
        for f in os.listdir(yd):
            m = re.fullmatch(r"(\d{8})-todo\.md", f)
            if not m:
                continue
            try:
                d = dt.datetime.strptime(m.group(1), "%Y%m%d").date()
            except ValueError:
                continue
            if d <= today and (best is None or d > best[0]):
                best = (d, os.path.join(yd, f))
    return best
