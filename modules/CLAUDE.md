# modules/ の置き場所ルール（新モジュールを作る AI 向け）

このリポジトリのモジュールは **種別軸** で 4 つのバケツに分かれている。
`modules/<kind>/<topic>/<layer>.nix`。ファイルを作るのは基本 AI（あなた）なので、
「どのバケツに置くか」の判断基準をここに集約する。**新しい関心事を足すときは必ずここを見て
バケツを1つ選ぶ**。迷ったら下の決定手順とタイブレーク判例に従う。

## 4 つのバケツ

| kind | 一言でいうと | 判定の軸 | 住人の例 |
|---|---|---|---|
| **base** | この機体の土台インフラ | これが無いと「私の mac」が成立しない前提そのものか | nix-core / macos-defaults / homebrew-base / host-users / remote-access |
| **apps** | 既製品の設定値 | 価値の中心が**外部プロダクト**で、ここは設定を書くだけか | shell / core-packages / git / tmux / nixvim / starship / ghostty / zed / herdr / claude / aerospace / handy / neru |
| **custom** | 自作システム | 価値の中心が**自分のコード**か（設定ではなく実装がある） | cp / chrome-anjin / network-block |
| **domain** | 生活ドメイン | 「何であるか」より「**なぜあるか**（どの生活領域のためか）」で括りたいか | latex / school/txst |

## 決定手順（上から順に、最初に当たったものを採る）

1. **土台か？** — nix 本体・OS 既定・パッケージ供給基盤・ユーザー/鍵など、「この機体が
   そもそも動く前提」なら **base**。個別アプリの設定はここではない。
2. **自作システムか？** — そのディレクトリの価値が自分の書いたスクリプト/実装にあるなら
   **custom**（設定ファイルではなく `scripts/` や `bin/`、独自ロジックが主役）。
3. **特定の生活ドメインのために存在するか？** — 技術的には何であれ、「学校のため」「執筆のため」
   のように**目的で括りたい**なら **domain**。学期・案件のライフサイクルを持つものもここ。
4. **上のどれでもない既製品の設定** → **apps**。既定の落とし場所。

## タイブレーク判例（過去に迷った実例）

- **herdr / claude → apps。** どちらも中に自作スクリプト（herdr-auto-name.sh、claude の skills）を
  持つが、**価値の中心は外部プロダクト**（herdr 本体・Claude Code）で、モジュールがやるのは
  その設定・配線。「自作物が同居している」だけでは custom にしない。
  判定軸は *価値の中心が自分のコードか、既製品の設定値か*。
- **cp 一家（tools / dashboard / snippets）→ custom/cp/。** 競プロ用の自作ツール群。
  設定ではなく実装が主役なので custom。関連する複数トピックは `custom/cp/<sub>/` に束ねる。
- **latex → domain。** 技術的には「TeX という既製品の設定」だが、存在理由が「執筆という生活
  ドメイン」なので domain に置く（**“なぜあるか” ＞ “何であるか”**）。同じ理由で school/txst も domain。
- **shell / core-packages → apps。** 「土台っぽい」が、これらは既製シェル・既製 CLI 群の設定/選択
  であって機体の前提インフラ（base）ではない。base は nix/OS/homebrew/ユーザー/鍵に限る。
- **network-block / chrome-anjin → custom。** 既製品名が付いていても、中身は自分で組んだ遮断
  ルール・隔離プロファイルという**自作システム**。

## レイヤー（ファイル名）の規約

トピックのディレクトリ内で、**ファイル名が適用層を宣言する**：

- `darwin.nix` … nix-darwin（システム）層。profile の `imports` に入る。
- `home.nix` … home-manager（ユーザー）層。profile の `home-manager.users.<name>.imports` に入る。
- 将来 NixOS を足すなら `nixos.nix` を**同じトピックディレクトリに同居**させる（層で分けず、
  関心事で1部屋にまとめるのがこのツリーの肝）。
- スクリプト・アセット（`scripts/`, `bin/`, `skills/`, `*.lua` 等）は**そのトピックの
  ディレクトリに同居**させる。モジュールから相対パスで参照する。

## 新モジュールを足す手順

1. バケツを1つ選ぶ（上の手順）。`modules/<kind>/<topic>/` を作る。
2. `home.nix` か `darwin.nix`（両方でも可）を書く。本文・見出し・`title:` は日本語、
   ファイル名は英語 ASCII slug（リポジトリ全体の言語規約）。
3. **`profiles/mac-workstation.nix` の該当セクションに import を1行足す**（作っただけでは
   どのホストにも入らない）。
4. 退役させるときは `git mv` で `modules/_archive/` へ移し、profile の import を消す
   （手順の全文は `modules/_archive/README.md`）。

## 外部公開している内部パス（動かすとき注意）

トピックを別バケツへ移すと相対/絶対パスがずれる。移動時は以下を追従させること：

- `flake.nix` の `homeModules.tmux = import ./modules/apps/tmux/home.nix;`（◆ nixos-cp が消費。
  **output 名は変えない**、import パスだけ追従）。
- `modules/apps/nixvim/home.nix` の out-of-store symlink 先 `.../modules/custom/cp/snippets`
  （絶対パス。cp を動かしたらここも直す）。
- `modules/base/remote-access/darwin.nix` の `import ../../../keys.nix`（バケツで1階層深いので
  `../` が3つ。トピックの階層が変わったら数え直す）。
