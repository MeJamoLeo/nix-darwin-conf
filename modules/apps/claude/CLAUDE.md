# 横断ルール（全プロジェクト共通）

## 未知の固有名詞は検証してから助言する

- ユーザーが出した固有名詞（アプリ・ツール・サービス・製品名）を高確信で知らないなら、助言や設計を組み立てる**前に**調査する（`command -v`・インストール確認・Web 検索）。すぐ調査できないなら「◯◯を知らないので確認させて」と明示する。内部で補完した想像（「たぶん GUI アプリだろう」等）の上に具体的助言を積むことを禁止する。
- 提案・設計系の回答では、依存している前提を**検証済み**と「**前提（未確認）**: …」に分けて示し、ユーザーが未検証前提を一目で潰せるようにする。
- ユーザーが「この回答が依存している前提を列挙して」と言ったら、隠れた前提を全列挙する。

## 個人文脈のマウントポイント（記憶は vault が正史）

auto-memory は無効化済み（`autoMemoryEnabled: false`）。個人の文脈・記憶の正史は
claude-obsidian の vault：`/Users/treo/Forge/claude-obsidian`。

- 個人文脈が必要なときだけ読む：①セッション冒頭に注入される `<personal-context>`（entry-map。
  `.claude/hooks/vault-context-inject.sh` が `scripts/entry-map.py` から機械生成）→
  ②`vault/wiki/index.md`→③個別ページ。一般的なコーディング質問のためには読まない。
  （旧 `vault/wiki/hot.md` は 2026-09-11 に廃止済み。**存在しないので読みに行かない**。
  hook 側は同日に entry-map へ切り替わっていたが、この記述が追従していなかった）
- **git worktree の中にいるときは、vault 本体を読む。** worktree 内の `vault/wiki` は
  そのブランチのコピーであって最新とは限らない（Orca は1タスク＝1 worktree で動く）。
  文脈の参照先は常に `/Users/treo/Forge/claude-obsidian`。
- **恒久的な事実・決定・好みに気づいたら訊かずに保存する**：claude-obsidian のセッション内ならその規約（save/wiki skill）で直接 vault へ。他プロジェクトからは `vault/.raw/inbox/` に捕獲メモ（md）を置く（inbox への追加は許容されている。次の claude-obsidian セッションが triage する）。保存したら一行報告のみ。
- 常時効かせたい規律に気づいたら、本ファイルへの追記を**提案**する（勝手に書かない。本ファイルは nix-darwin-conf 管理）。

## 一次資料は ~/Store が正本（fleet 共有のファイルサーバ）

PDF・配布ファイル・原本・授業の物は `~/Store/` に置く。**振り分けの正本は
`~/Store/README.md` の「振り分け」表**（上から1問ずつ、最初の Yes で決まる）。迷ったら
まずその表を読む。要点だけ：

- **授業に属する物は、資料でも自分の答案でも `~/Store/20_Courses/<COURSE>/`。**
  学期中だけ別の場所で作業して後で移す、はしない（2026-10-25 に `~/txst` を廃止した。
  移動のひと手間を要する設計は、その手間が踏まれないぶんだけ二重化になるため）。
- 再取得できない原本＝`10_Records/`／蔵書＝`40_Library/`／授業以外の自作物＝`30_Work/`／
  判定不能＝`90_Staging/`（TTL 30日で自動削除）。
- `~/Forge` と `~/Store` の切れ目は「**git remote で機体を越えるか**」。Yes なら Forge の
  まま、No で取っておくなら Store。Forge の成果物で完成して置いておく物だけ Store へ移す。
- Store 全体を git で管理しない（配下の個別 repo は可）。Claude が Store に作る物は
  Markdown。docx/xlsx/pptx は作らない。詳細は `~/Store/README.md` の「契約」。

## 生活雑務は end-to-end で拾う

- 雑務（解約・乗り換え・書類取得・料金調査など）は調査→実行→カレンダー/vault への固定まで一気通貫でやる。人力に残す手番は **(a) credential/OTP の入力・(b) 破壊的/金銭的な最終判断** の2種だけ。
- 人間への依頼は**【端末・画面・操作】形式・30秒単位に圧縮**してまとめて出す。
- 詳細な運用ルール・環境制約（TXST 外部連携全面制限・ブラウザに Google ログインさせない等）は vault の `claude-life-admin-operating-rules` と Area `anjin-operations` が正史。

## モデル規律（トークン/レートリミット）

- 原則：**判断＝Fable/Opus、作業＝Sonnet、機械作業＝Haiku**。反復ループ・fan-out・web 大量取得は本体で回さず、Agent tool / Workflow の `agent()` に `model: "sonnet"` を明示して委譲する（**無指定は本体モデル継承**）。作業系のエスカレーションは opus のみ・単発。
- **Fable は「判断の単発委譲」でだけ使う。** メインセッションのモデルには据えず、`/advisor`（設計判断のセカンドオピニオン）経由で **1論点1体・並列禁止・実装させない**。それ以外の fan-out / 作業ループに Fable を委譲先として使わない（`~/.claude/settings.json` の `permissions.ask` に `Agent(model:fable)` を置いて、偶発的な増殖にゲートを掛けてある）。
- 用途別の対応表と詳細は claude-obsidian の CLAUDE.md「モデル規律」が正史。

## 設定・知識の置き場所ポリシー

- **user-level（`~/.claude` 等）で便利なもの**は手動で置かず **nix-darwin-conf**（`~/nix-darwin-conf`）で宣言的に管理する。user-level に生ファイルを作らない。
- **記憶・知識**は vault（上記）。**プロジェクト固有の skill / agent** はそのプロジェクトの `.claude/` に置く。
- `~/.claude/settings.json` だけは可変ファイルとして手動管理（home-manager で所有しない決定済み）。
