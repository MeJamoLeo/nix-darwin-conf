"""discord-apply — spec JSON を正本に Discord のカテゴリ/チャンネルを収束させる。

## 設計

- **state を持たない。** 毎回 `GET /guilds/<id>/channels` で現状を読んでから spec と
  突き合わせる。Discord 自身が state なので、別の正史（terraform.tfstate 相当）を
  作らない＝drift しようがない。
- **削除しない。** spec に無いチャンネルは `!extra` として報告するだけで触らない。
  破壊的操作は実装そのものが存在しない（`discord-api` 側の柵と二重）。
- **rename は自動化しない。** name をキーに突き合わせているので、spec 上で改名すると
  「旧が spec に無い（消さない）＋新が無い（作る）」となり**重複する**。改名は差分として
  出すだけにして、人間が承認してから `discord-api --write PATCH` を1本打つ。
- **既定は plan。** 実行は `--apply` を明示したときだけ。
- **命名規則の検査器をここに置く。** spec が規約を満たしているかを適用前に検証する。
  規約の文書と検査器を分けると drift するので、spec ファイルが規約の正本であり、
  この関数がその唯一の実装（fleet-home-directory-design 原則3）。

## spec の形

    {
      "guild_id": "123456789012345678",
      "categories": [
        {"name": "project-cs4371",
         "channels": [{"name": "hw-1", "topic": "..."}, {"name": "notes"}]}
      ],
      "uncategorized": [{"name": "general"}]
    }

配列の順序がそのまま表示順（position）になる。position を手で書かないのは、
「順序は名前に焼き込まない」という命名規則の裏返し。

## 使い方

    discord-apply servers/foo.json           # plan（差分を出すだけ）
    discord-apply servers/foo.json --apply   # 実行
"""

import argparse
import json
import re
import subprocess
import sys

TYPE_TEXT = 0
TYPE_CATEGORY = 4

# 命名規則の検査器（kebab-case ASCII slug）。Discord 側もテキストチャンネル名を
# 小文字化・空白をハイフン化するので、規約に寄せておくと表示と spec が一致する。
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
NAME_MAX = 100


class Fail(Exception):
    pass


def api(method, route, body=None, write=False):
    """discord-api ラッパー経由で叩く。token はこのプロセスを通らない。"""
    cmd = ["discord-api"]
    if write:
        cmd.append("--write")
    cmd += [method, route]
    if body is not None:
        cmd.append(json.dumps(body, ensure_ascii=False))
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise Fail(f"{method} {route} が失敗\n{r.stderr.strip()}")
    out = r.stdout.strip()
    return json.loads(out) if out else None


def check_name(name, where):
    if not isinstance(name, str) or not name:
        raise Fail(f"{where}: name が空")
    if len(name) > NAME_MAX:
        raise Fail(f"{where}: name が {NAME_MAX} 文字を超えている: {name!r}")
    if not NAME_RE.match(name):
        raise Fail(
            f"{where}: 命名規則違反 {name!r}\n"
            "  kebab-case ASCII のみ（小文字英数字をハイフンで連結・"
            "先頭末尾と連続のハイフン禁止）"
        )


def load_spec(path):
    try:
        with open(path, encoding="utf-8") as f:
            spec = json.load(f)
    except OSError as e:
        raise Fail(f"spec を読めない: {e}")
    except json.JSONDecodeError as e:
        raise Fail(f"spec が JSON として不正: {e}")

    gid = spec.get("guild_id")
    if not isinstance(gid, str) or not gid.isdigit():
        raise Fail("guild_id が無い（Discord の snowflake を文字列で書く）")

    seen = {}
    for cat in spec.get("categories", []):
        check_name(cat.get("name"), "categories[]")
        for ch in cat.get("channels", []):
            check_name(ch.get("name"), f"{cat['name']}.channels[]")
            if ch["name"] in seen:
                raise Fail(
                    f"チャンネル名の重複: {ch['name']!r} "
                    f"({seen[ch['name']]} と {cat['name']})。"
                    "このツールは name をキーに突き合わせるので重複を許さない"
                )
            seen[ch["name"]] = cat["name"]
    for ch in spec.get("uncategorized", []):
        check_name(ch.get("name"), "uncategorized[]")
        if ch["name"] in seen:
            raise Fail(f"チャンネル名の重複: {ch['name']!r}")
        seen[ch["name"]] = "(top level)"
    return spec


def desired(spec):
    """spec を (カテゴリ列, チャンネル列) に平坦化する。順序＝position。"""
    cats = []
    chans = []
    for pos, cat in enumerate(spec.get("categories", [])):
        cats.append({"name": cat["name"], "position": pos})
        for cpos, ch in enumerate(cat.get("channels", [])):
            chans.append({
                "name": ch["name"],
                "topic": ch.get("topic"),
                "parent": cat["name"],
                "position": cpos,
            })
    for pos, ch in enumerate(spec.get("uncategorized", [])):
        chans.append({
            "name": ch["name"],
            "topic": ch.get("topic"),
            "parent": None,
            "position": pos,
        })
    return cats, chans


def fetch_current(gid):
    live = api("GET", f"/guilds/{gid}/channels")
    cats, texts = {}, {}
    for c in live:
        if c["type"] == TYPE_CATEGORY:
            if c["name"] in cats:
                raise Fail(f"Discord 側にカテゴリ名の重複: {c['name']!r}。手で解消して")
            cats[c["name"]] = c
        elif c["type"] == TYPE_TEXT:
            if c["name"] in texts:
                raise Fail(f"Discord 側にチャンネル名の重複: {c['name']!r}。手で解消して")
            texts[c["name"]] = c
    return cats, texts, live


def build_plan(spec):
    gid = spec["guild_id"]
    want_cats, want_chans = desired(spec)
    have_cats, have_texts, live = fetch_current(gid)

    actions = []
    for c in want_cats:
        if c["name"] not in have_cats:
            actions.append(("create-category", c, None))
    for ch in want_chans:
        cur = have_texts.get(ch["name"])
        if cur is None:
            actions.append(("create-channel", ch, None))
        else:
            actions.append(("place", ch, cur))

    want_names = {c["name"] for c in want_cats} | {c["name"] for c in want_chans}
    extras = [c for c in live
              if c["type"] in (TYPE_TEXT, TYPE_CATEGORY) and c["name"] not in want_names]
    return gid, want_cats, want_chans, have_cats, have_texts, actions, extras


def parent_name_of(cur, have_cats):
    by_id = {c["id"]: n for n, c in have_cats.items()}
    return by_id.get(cur.get("parent_id"))


def print_plan(want_cats, want_chans, have_cats, have_texts, extras):
    print("=== plan ===")
    for c in want_cats:
        mark = "=" if c["name"] in have_cats else "+"
        print(f"  {mark} category  {c['name']}")
    for ch in want_chans:
        cur = have_texts.get(ch["name"])
        where = ch["parent"] or "(top level)"
        if cur is None:
            print(f"  + channel   {where} / {ch['name']}")
            continue
        cur_parent = parent_name_of(cur, have_cats)
        if cur_parent != ch["parent"]:
            print(f"  ~ move      {ch['name']}: "
                  f"{cur_parent or '(top level)'} -> {where}")
        elif cur.get("position") != ch["position"]:
            print(f"  ~ reorder   {where} / {ch['name']} "
                  f"(position {cur.get('position')} -> {ch['position']})")
        else:
            print(f"  = ok        {where} / {ch['name']}")
    for e in extras:
        kind = "category" if e["type"] == TYPE_CATEGORY else "channel"
        print(f"  ! extra     {kind} {e['name']} — spec に無い。触らない"
              "（改名したなら手で PATCH するか spec に足す）")
    print()


def apply(gid, want_cats, want_chans, have_cats, have_texts):
    # 1) カテゴリを先に作る（チャンネルの parent_id に要る）
    for c in want_cats:
        if c["name"] in have_cats:
            continue
        print(f"  + category  {c['name']}")
        created = api("POST", f"/guilds/{gid}/channels",
                      {"name": c["name"], "type": TYPE_CATEGORY,
                       "position": c["position"]}, write=True)
        have_cats[c["name"]] = created

    # 2) 足りないチャンネルを作る
    for ch in want_chans:
        if ch["name"] in have_texts:
            continue
        body = {"name": ch["name"], "type": TYPE_TEXT, "position": ch["position"]}
        if ch["parent"]:
            body["parent_id"] = have_cats[ch["parent"]]["id"]
        if ch.get("topic"):
            body["topic"] = ch["topic"]
        where = ch["parent"] or "(top level)"
        print(f"  + channel   {where} / {ch['name']}")
        created = api("POST", f"/guilds/{gid}/channels", body, write=True)
        have_texts[ch["name"]] = created

    # 3) 親の引っ越しは 1 件ずつ個別 PATCH で行う。
    #    Modify Guild Channel Positions（一括）は parent_id の変更を
    #    **1 リクエストにつき 1 チャンネルまで**に制限している：
    #      {"message": "Only one channel can have a parent_id modified at a time",
    #       "code": 40009}
    #    公式ドキュメントに記載が無く、2026-09-04 に実サーバで踏んで判明した。
    #    新規作成したチャンネルは POST 時に parent_id を渡しているので、ここに
    #    来るのは「既存チャンネルの引っ越し」だけ（例: 既定の general → course）。
    cat_name_by_id = {c["id"]: n for n, c in have_cats.items()}
    for ch in want_chans:
        cur = have_texts[ch["name"]]
        if cat_name_by_id.get(cur.get("parent_id")) == ch["parent"]:
            continue
        pid = have_cats[ch["parent"]]["id"] if ch["parent"] else None
        print(f"  ~ move      {ch['name']} -> {ch['parent'] or '(top level)'}")
        api("PATCH", f"/channels/{cur['id']}", {"parent_id": pid}, write=True)

    # 4) 並び順だけを一括で収束させる（parent_id は載せない）
    moves = [{"id": have_cats[c["name"]]["id"], "position": c["position"]}
             for c in want_cats]
    moves += [{"id": have_texts[ch["name"]]["id"], "position": ch["position"]}
              for ch in want_chans]
    if moves:
        print(f"  ~ positions {len(moves)} 件を一括更新")
        api("PATCH", f"/guilds/{gid}/channels", moves, write=True)


def main():
    p = argparse.ArgumentParser(
        prog="discord-apply",
        description="spec JSON を正本に Discord のチャンネル構成を収束させる（削除はしない）")
    p.add_argument("spec", help="spec JSON のパス")
    p.add_argument("--apply", action="store_true",
                   help="実際に適用する（既定は plan のみ）")
    args = p.parse_args()

    try:
        spec = load_spec(args.spec)
        gid, want_cats, want_chans, have_cats, have_texts, actions, extras = \
            build_plan(spec)
        print_plan(want_cats, want_chans, have_cats, have_texts, extras)

        todo = [a for a in actions if a[0] != "place" or
                parent_name_of(a[2], have_cats) != a[1]["parent"] or
                a[2].get("position") != a[1]["position"]]
        if not todo:
            print("差分なし。何もしない。")
            return 0
        if not args.apply:
            print(f"{len(todo)} 件の変更がある。実行するなら --apply を足す。")
            return 0

        print("=== apply ===")
        apply(gid, want_cats, want_chans, have_cats, have_texts)
        print("完了。もう一度 plan を回すと差分なしになるはず（冪等性の確認）。")
        return 0
    except Fail as e:
        print(f"discord-apply: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
