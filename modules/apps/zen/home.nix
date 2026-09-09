{pkgs, ...}:
# Zen（Firefox フォーク）— 既製品の設定値なので apps バケツ。
#
# ## なぜ homebrew cask から flake の home-manager モジュールへ移したか（2026-08-27）
#
# Zen の **Space / Folder / ピン留め**は prefs ではなく実行時ステートに入っている：
#   - Space・Folder・pin  → プロファイル内 `zen-sessions.jsonlz4`（LZ4 圧縮 JSON）
#   - Space のブックマーク → `places.sqlite` の `zen_bookmarks_workspaces` テーブル
# よって cask + `home.file` で user.js を置く旧構成では **prefs までしか宣言できない**。
# zen-browser-flake の HM モジュールは activation script で jsonlz4 を展開 → jq で
# upsert → 再圧縮するので、Space と Folder を宣言的に固定できる（flake.nix の input
# コメントも参照）。
#
# ## Mozilla アカウントの Sync では代替にならない（調査済み・2026-08-27）
#
# Zen は Firefox Sync に乗るので bookmarks / passwords / history / 拡張 / 開いてるタブは
# 同期するが、**Space は stable では同期しない**（Twilight で実装中。desktop#11407 /
# #12339 / #12749）。Folder とタブ配置はローカルステートで、公式の Window Sync も
# 「同一デバイスのウィンドウ間」限定。したがって固定するなら宣言的にやるしかない。
#
# ## 既存プロファイルの乗っ取り（重要）
#
# mkFirefoxModule は darwin で `profilesPath = <configPath>/Profiles` を使い、
# profiles.ini に `Path = Profiles/<profile.path>` を書く。`path` を**実在の
# プロファイルディレクトリ名**に合わせることで、10MB の places.sqlite・logins.db・
# 拡張7個が入った既存プロファイルをそのまま引き継ぐ（新規プロファイルを作らせない）。
#
# ⚠ この値は `~/Library/Application Support/zen/installs.ini` の `[<ハッシュ>] Default`
#   と一致していなければならない（profiles.ini 側に `[Install…]` は生成されないので、
#   起動時にどのプロファイルが選ばれるかは installs.ini が決める）。Zen 側でプロファイルを
#   作り直したらここを更新する。
#
# ### ⚠⚠ 実在しない名前を書くと「空のプロファイルが生える」（2026-08-31 に踏んだ）
#
# `path` に実在しないディレクトリ名（当時は `tof5kg3s.Default (release)-1`）を書いていた。
# HM は `.keep` を置くためにその名前のディレクトリを**作ってしまう**ので、Zen から見ると
# 「登録済みだが中身が無いプロファイル」になり、そこを新規初期化して起動する。
# エラーにならず静かに空のブラウザが立ち上がるのでタチが悪い。実測（2026-08-31）：
#   tbq2aiii.Default (release)     248M / 履歴 2498 / ユーザー拡張 7  ← 本物
#   tof5kg3s.Default (release)-1    58M / 履歴   20 / ユーザー拡張 0  ← 空。誤って指していた先
# 判別は `places.sqlite` の `moz_places` 行数と `extensions.json` を見るのが速い。
#
# ### 🔴 名前は機体固有「だった」→ 統一した（2026-09-01 に分離 → 2026-09-04 に解消）
#
# Zen はプロファイル作成時にランダムな8文字を頭に付けるので、各機が独立に作った結果
# 名前が割れていた。しかも `tof5kg3s.Default (release)-1` は**両機に実在して中身が違う**：
#   ogasawara    tof5kg3s.Default (release)-1  601M ← 本物（現役）
#   tanegashima  tbq2aiii.Default (release)    253M ← 本物（現役）
#   tanegashima  tof5kg3s.Default (release)-1   54M ← 残骸
# 名前だけでは正しい方を選べないので、09-01 に `zenProfilesByHost` へ機体別に切り出した。
#
# ★ だがそれは**ばらつきを設定に写し取る**形で、fleet-home-directory-design の原則
#   （ばらつく場所が定義上存在しない形にする）に反する。ランダム接頭辞は「初回に何も
#   指定しなかった場合の既定」でしかなく、`path` は**こちらが宣言する値**である
#   （dejima に `dejima.Default (release)` という捏造名を書けていたのがその証拠）。
#   よって 09-04 に**各機のディレクトリを共通名へ 1 回だけ改名**して機体差を消した。
#   移行手順（機体ごとに 1 回）:
#     1. Zen を終了する（起動中は書き戻される）
#     2. `~/Library/Application Support/zen/Profiles/<旧名>` を `zen.Default` へ mv
#     3. `installs.ini` の `Default=Profiles/<旧名>` を全ハッシュぶん新名へ書き換える
#        （profiles.ini だけ直しても効かない。下の dedicated profile の節を参照）
#     4. rebuild して Zen を起動し、履歴と拡張が生きていることを確認
#   統一されるのは**設定の形**だけで、履歴・拡張・cookie は元から機体別（同期しない設計）。
#   ※ configPath は上流モジュールが大文字の `…/Zen` を使うが、macOS の APFS は
#     既定で case-insensitive なので実体の `…/zen` と同じディレクトリに解決する（実測確認済み）。
#
# ⚠ profiles.ini は nix 管理のシンボリックリンクになる。既存ファイルは
#   home-manager の backupFileExtension により `.hm-backup` に退避される。
#   `installs.ini` は非管理のまま残る（Zen が書く可変ファイル）。
#
# ### ⚠⚠ dedicated profile ＝ 移行時に一度だけ手当てが要る（2026-08-27 に踏んだ）
#
# Firefox 67+ は **.app のパスから計算したインストールハッシュごとに専用プロファイルを持つ**。
# `installs.ini` に自分のハッシュが無いと、**profiles.ini の `Default=1` にフォールバックせず
# 意図的に新規プロファイルを作る**（作られた profile の times.json が
# `"source": "firstrun-skipped-default"` と言う）。cask 版と nix 版は .app パスが違う＝
# 別インストール扱いなので、移行直後の初回起動でこれが起きる。
# しかも新規プロファイルを profiles.ini に登録しようとして、**profiles.ini が /nix/store への
# 読み取り専用リンク**なので書けず、`Profile Missing` ダイアログで停止する。
#
# 対処は `installs.ini` の当該ハッシュ行を既存プロファイルに向けるだけ（1回きり）：
#
#   [DFEDCF58DA149FC0]                            ← nix 版 Zen のインストールハッシュ
#   Default=Profiles/tbq2aiii.Default (release)   ← ここを既存プロファイルにする
#                                                    （＝その機体の zenProfilesByHost の値）
#
# ⚠ `Locked=1` が付いていても Zen が黙って書き換えることがある（2026-08-31 に、この行が
#   空プロファイル `tof5kg3s.…-1` を向いた状態を実測）。上の `path` を変えたら、
#   **Zen を終了した状態で** この行も必ず追従させること。片方だけ直しても効かない。
#
# このハッシュが**バージョン更新で変わらない**のは flake 側の設計による。package.nix:82 が
# `$HOME/Applications/Home Manager Apps/<app>.app` という安定パス経由で起動するラッパーを
# 作っている（"Use symlink path to avoid installs.ini accumulation on Nix rebuilds"）。
# Dock の固定先も同じ安定パスなので揃っている。→ 手当ては移行時の1回だけで済む。
#
# ## Space / pin を宣言しはじめたときの運用上の注意
#
#   - `darwin-rebuild switch` の前に **Zen を終了**させること（activation script が
#     zen-sessions.jsonlz4 に排他アクセスを要る）。何も宣言していない間は session writer
#     自体が走らないので、この制約は掛からない（store.nix の profilesWithSessionData 参照）。
#   - Space は `uuid` 一致でマージされるので、既存 Space の id を書けば重複しない。
#     pin は `zenSyncId` 一致で照合するが、Zen が自動生成する既存 id はタイムスタンプ形式
#     （例 `1783379884207-81`）で UUID と噛み合わない。**既存の pin を宣言に載せ替えるには
#     `pinsForce = true` が要る**（さもないと同じ URL の pin が二重に生える）。
#
# ## .app の置き場所が変わる
#
# `darwin.packageMode = "signed"`（既定）は upstream の .app を無改変で入れるので
# Team ID 依存の統合（1Password・iCloud Passwords・Touch ID・Gatekeeper）が壊れない。
# 代償として wrapFirefox 系の機能（extraPrefs / extraPrefsFiles / pkcs11Modules）は使えない。
# 実体は `~/Applications/Home Manager Apps/Zen Browser (Beta).app`（Zed・AeroSpace と
# 同じ扱い）になり、`/Applications/Zen.app` は生えない。**バンドル名が cask 版と違う**
# 点に注意（upstream の .app を無改変で入れるので改名されない）。バンドル ID は同じ
# `app.zen-browser.zen`、署名の TeamIdentifier も `9V5K9TP787` のままであることを実測確認済み。
# Dock の固定先は macos-defaults/darwin.nix で追従させてある。
#
# ⚠ 同じバンドル ID の .app が2つ（旧 cask の /Applications/Zen.app と nix 版）あると
#   LaunchServices の既定ブラウザ解決が不定になる。移行を確認したら
#   `brew uninstall --cask zen` で旧実体を消すこと。
#
# ## Space / Folder の設計（2026-08-29・実測ベース）
#
# 分類は想像でなく `places.sqlite` の実履歴から起こした。直近14日（秋学期開始後）を
# 「同一 URL の連打を潰した訪問ページ数」で数えた結果がそのままクラスタになっている：
#   canvas.txstate.edu 103 / duckduckgo 75 / docs.google 49 / x.com 31 / onedrive 20 /
#   アパートポータル 18 / drive 16 / claude.ai 15 / zybooks 14 / netgate 13 / usmobile 12 …
#
# ★測定時に潰したノイズ2件（これを外さないと設計を誤る）：
#   - `blog.adafruit.com` は60日で 1135 visits と2位級に見えるが、**実体は同一 URL 1本に
#     608 visits**（Escura の firmware 解析で読んだ記事）。リロードループの副作用で意味はゼロ。
#   - `www.youtube.com` は60日 1566 で1位だが **直近7日は 0**。しかも youtube-gate の遮断対象。
#
# 階層は2段：**Space ＝ 生活ドメイン（長寿命）／ Folder ＝ その中の案件（学期・旅行など短寿命）**。
# 科目や旅行を Space にすると終わるたびに Space を消す羽目になるので Folder に落とす。
#
# 娯楽（X / YouTube）には**場所を与えない**。Space は「タブの置き場」であって開く行為は
# 止めないので、専用 Space を作ると摩擦が下がって逆に働く。遮断は youtube-gate の担当。
#
# ## ⚠ 上の 2026-08-29 の数値は再現しない（2026-08-31 の棚卸しで判明）
#
# 空プロファイル事故（前述）から復帰したあと同じ測定をやり直したところ、上に並んでいる
# 数値のうち **netgate 13 / onedrive 20 / blog.adafruit.com 60日1135** は
# `moz_places` に**行そのものが存在しない**（＝一度も訪問していない）。履歴の期限切れなら
# 訪問行が消えても place 行と `visit_count` は残るので、これは「消えた」ではなく
# 「無かった」を意味する。他に履歴を持つプロファイルも存在しない（残り3つは空か履歴20件）。
# canvas 103→107・youtube「直近7日ゼロ」など**合っている数値もある**ので、全部が誤りでは
# ないが、上のリストは一次資料として信用しないこと。
# ⚠ 未確認：当時どこを測っていたのかは特定できていない。
#
# ## School の再設計（2026-08-31・`tbq2aiii` の実データのみで再測）
#
# 直近14日の School 系ホスト（ページ数）：
#   canvas.txstate.edu 107 / authentic.txstate.edu 20（SSO）/ duosecurity 25（MFA）/
#   zoom.us 23（app 16・txstate 4・google 3）/ txst.sharepoint.com 14 /
#   login.microsoftonline.com 12 / zybooks 8 / printing 6 / kortext 5 / follett 3
#
# ここから3つ直した：
#   1. **Zoom が丸ごと抜けていた**（実測3位相当なのに pin も route も無し）→ Essential + route。
#   2. **📚Fall 2026 の中身が事務だった**（Printing/YuJa/Bursar）→ 履修科目に入れ替え、
#      事務は 🏫Campus に分離。学期末の退役がフォルダ1つの削除で済む形に戻した。
#   3. **教科書の導線（Follett → Kortext）が未宣言**だった → 🏫Campus に追加。
#
# 実測ゼロ（`moz_places` に行が無い）だが**残した**もの：CS4371 Lab の3件・Campus Job の
# Handshake・`txst-my.sharepoint.com` route。学期序盤で未使用なだけの可能性があるため
# （本人判断）。次の棚卸しでもゼロなら落とす。
#
# container（Cookie 隔離）は **School だけに使う**。当初は「不要」と判断していた——実測で
# 既定コンテナ4つ（Personal/Work/Banking/Shopping）が全部未使用、Google も第1アカウント 184
# に対し第2（`/u/1/`）は 14 visits で Drive 閲覧のみ、かつ TXST 本体は Microsoft だったため。
# **その `/u/1/` が TXST の Google Workspace だと判明して反転**（本人確認・2026-08-29）。
# 私用 Google と学校 Google が同じ Cookie 壺に同居していたので、School を別の器に分ける。
let
  # 全機共通のプロファイルディレクトリ名（2026-09-04 に統一。経緯は上の「名前は機体固有
  # だった → 統一した」）。ランダム接頭辞は Zen の初回既定でしかなく、`path` はこちらが
  # 宣言する値なので、実ディレクトリを改名して機体差を消した。
  #
  # ★ 揃うのは**宣言層だけ**。Firefox Sync は張らない。Space / Folder / pin / prefs は
  #   このファイルが全機に同じものを配る。履歴・ブックマーク・拡張は機体ごとに別のまま
  #   （どちらも現役の実データで、片方に寄せると片方の実績が消えるので統合しない）。
  #   パスワードは Bitwarden に寄せる方針なのでブラウザの logins を同期経路に載せない
  #   （vault の secret-management-fleet-strategy が正本）。
  #
  # ⚠ 新しい機体を足すときは、その実機で Zen を一度起動してプロファイルを作らせてから
  #   `~/Library/Application Support/zen/Profiles/<ランダム名>` を `zen.Default` へ改名し、
  #   `installs.ini` の該当ハッシュも同じ先を向かせる。**両方直さないと効かない**
  #   （profiles.ini だけでは dedicated profile の解決に負ける。上の節を参照）。
  zenProfile = {
    name = "Default";
    path = "zen.Default";
  };
in {
  programs.zen-browser = {
    enable = true;

    # 既定値だが、署名を保つ選択は Team ID 統合の前提なので明示しておく。
    darwin.packageMode = "signed";

    # policies は `targets.darwin.defaults` 経由で `app.zen-browser.zen` ドメインに書かれる
    # （.app の中には触らない）。**Zen がこれを読むことは実測で確認済み**（2026-08-27：
    # モジュール既定の DisableAppUpdate が効き、prefs.js の
    # `app.update.background.previous.reasons` に "cannot usually check for updates due to
    # policy" が焼かれた）。desktop#12363 は Managed Preferences を読まないという別件。
    # 追加の policy が要るならここに書けば効く。遮断は引き続き user.js 経路（youtube-gate）。
    policies = {};

    profiles.default = {
      id = 0;
      inherit (zenProfile) name path;
      isDefault = true;

      # user.js の中身は関心事ごとに各モジュールが寄せる（nix の attrset マージ）：
      #   - modules/custom/youtube-gate/home.nix … PAC による YouTube 遮断
      # ここには Zen 固有の一般設定だけを置く。
      settings = {
        # 既定ブラウザ確認のダイアログを出さない（既定は macOS 側で管理する）。
        "browser.shell.checkDefaultBrowser" = false;
        # Space を切り替えたとき、前回そこで見ていたタブに戻る（区画の記憶）。
        "zen.workspaces.continue-where-left-off" = true;
        # 下の extensions.packages で置いた拡張を起動時に自動で有効化する。
        #
        # ⚠⚠ これは「プロファイルに置かれた拡張の承認プロンプト」を消す設定＝防御の弱体化。
        #   当初「extensions ディレクトリが nix 管理になるから緩和される」と考えたが、
        #   **2026-09-05 の実測でそれは成立しないと確定した**。`recursive = true` は
        #   個別ファイルを symlink するだけで、ディレクトリ自体は書き込み可能なまま。
        #   実際、初回 switch 後も宣言に無い xpi 3 つ（AdGuard / Obsidian Web Clipper /
        #   DuckDuckGo）が実ファイルとして居残っていた。
        #   → **宣言から外した拡張は自動では消えない。手で消す必要がある**（about:addons
        #     から削除させるのが確実。Zen が extensions.json も併せて後始末するため）。
        #   → ここに任意の xpi を置けば承認なしで有効化されうる、という状態は残る。
        "extensions.autoDisableScopes" = 0;
      };

      # ── 拡張機能（2026-09-05 に宣言化）──────────────────────────────
      #
      # それまでは機体ごとに手で入れていた。宣言化した動機は「拡張のバージョンが
      # 機体で割れない」ことと、下の permission canary を張れること。
      #
      # ## LibreWolf と共通化していない理由（重要）
      #
      # 一見すると modules/custom/youtube-gate/librewolf.nix と拡張が重なるので
      # 共通モジュールに切り出したくなるが、**やってはいけない**：
      #   - あちらは汎用ブラウザではなく youtube-gate の逃げ道（PAC を無視できる
      #     唯一のアプリ・全ウィンドウがプライベート）。目的が違う
      #   - あちらの拡張は `extraPolicies.ExtensionSettings` で入っており、
      #     uBlock Origin と検索エンジンは**上流 LibreWolf の policies.json** 由来。
      #     こちらの `extensions.packages`（プロファイルの extensions ディレクトリを
      #     nix リンク化する）と経路が違い、混ぜると競合する
      #   - `programs.librewolf` を足すと同じバンドル ID の .app が 2 つになり、
      #     既定ブラウザの解決が不定になる（旧 zen cask 移行で踏んだのと同じ穴）
      # よって「共通の定義を配る」のではなく、**Zen が LibreWolf の既存の選択に
      # 合わせる**形にしてある（下の AdGuard → uBO がまさにそれ）。
      #
      # ## 落とした拡張（2026-09-05・本人判断）
      #
      #   - AdGuard AdBlocker → **uBlock Origin に置換**。youtube-gate 側が
      #     「ブロッカーは uBO に固定した（2026-08-03）」と既に決めており、機体を
      #     またいで 2 種類の広告ブロッカーを持つ理由が無い。副次的に、AdGuard は
      #     rycee の set に存在せず自前パッケージ化が要るという事情もある
      #   - Obsidian Web Clipper → 使っていない
      #   - DuckDuckGo Privacy & Tracker Protection → 不要（uBO と重複気味）
      #
      # ## Tampermonkey を Zen だけに置く理由
      #
      # 競技プログラミング用（🏆Competitive Programming Space・Build Space の
      # greasyfork route と対応）。実際に入っているスクリプトは 5 本すべて
      # atcoder.jp / codeforces / yukicoder に `@match` が限定されている（2026-09-05 監査）。
      #
      # ⚠ ただし **Tampermonkey は権限が突出して重い**：`<all_urls>` に加えて
      #   `cookies`（全サイトの Cookie）と `contextualIdentities`（コンテナ API）を持つ。
      #   つまり**下の containers による School の隔離は、拡張に対しては成立しない**。
      #   コンテナが隔離するのは Cookie であって拡張ではない。
      # ⚠ ユーザースクリプトは greasyfork から自動更新される＝ここで xpi を pin しても
      #   **実行されるコードはこの経路を迂回する**。nix で固めた供給網の外側にある入口。
      extensions = {
        # `pkgs.firefox-addons` は flake.nix で入れている rycee の overlay 由来
        # （`packages.<system>` を直に使わない理由は flake.nix のコメント参照）。
        packages = with pkgs.firefox-addons; [
          ublock-origin # 広告・トラッカー遮断（LibreWolf 側と同一に揃えた）
          vimium # キーボードナビ
          videospeed # 動画の再生速度
          youtube-recommended-videos # ＝ Unhook（おすすめ・Shorts を消す）
          tampermonkey # ⚠ Zen 限定。CP 用。権限が重い（上のコメント参照）
        ];

        # ── permission canary ────────────────────────────────────────
        #
        # ★ これは**ランタイムの権限制限ではない**。mkFirefoxModule の assertion で、
        #   ここに書いた一覧と拡張が実際に要求する meta.mozPermissions が食い違うと
        #   **ビルドが落ちる**（mkFirefoxModule.nix の extensions.packages 走査部）。
        #   拡張の権限は署名付き xpi の属性なので、設定で剥がすことはできない
        #   （剥がすと manifest のハッシュが変わって AMO 署名が壊れる）。
        #
        # ★ 狙いは供給網の見張り：バージョンが上がって権限が増えたら気づける。
        #   `exactPermissions = true` は増減の両方向を検出する（宣言に無い権限を
        #   要求してきた場合も、宣言したのに要求されなくなった場合も落ちる）。
        #
        # ⚠ したがって `nix flake update firefox-addons` でビルドが落ちたら、それは
        #   故障ではなく**検知**。落ちた差分を読んでから下の一覧を更新すること。
        #   機械的に追記して黙らせるのは canary を殺すのと同じ。
        exactPermissions = true;
        settings = {
          "uBlock0@raymondhill.net".permissions = [
            "alarms"
            "dns"
            "menus"
            "privacy"
            "storage"
            "tabs"
            "unlimitedStorage"
            "webNavigation"
            "webRequest"
            "webRequestBlocking"
            "<all_urls>"
            "http://*/*"
            "https://*/*"
            "file://*/*"
            "https://easylist.to/*"
            "https://*.fanboy.co.nz/*"
            "https://filterlists.com/*"
            "https://forums.lanik.us/*"
            "https://github.com/*"
            "https://*.github.io/*"
            "https://github.com/uBlockOrigin/*"
            "https://ublockorigin.github.io/*"
            "https://*.reddit.com/r/uBlockOrigin/*"
          ];
          # ⚠ `clipboardRead` は Vimium の `p` / `P`（クリップボードの URL を開く）と
          #   `yy`（現在の URL をコピー）に要る機能権限。外したくなるが、外す＝拡張を
          #   捨てるということ。Vimium C も同じ権限を持つので乗り換えても解決しない
          #   （2026-09-05 に rycee の set で確認）。受け入れて canary で見張る判断。
          "{d7742d87-e61d-4b78-b8a1-b469842139fa}".permissions = [
            "tabs"
            "bookmarks"
            "history"
            "storage"
            "sessions"
            "notifications"
            "scripting"
            "webNavigation"
            "search"
            "clipboardRead"
            "clipboardWrite"
            "<all_urls>"
            "file:///"
            "file:///*/"
          ];
          "{7be2ba16-0f1e-4d93-9ebc-5164397477a9}".permissions = [
            "storage"
            "http://*/*"
            "https://*/*"
            "file:///*"
          ];
          # Unhook。YouTube 以外に触らない＝5 個の中で唯一ホストが絞られている。
          "myallychou@gmail.com".permissions = [
            "storage"
            "webRequest"
            "https://www.youtube.com/*"
            "https://m.youtube.com/*"
          ];
          # ⚠ `cookies` と `contextualIdentities` に注目。この 2 つがあるので
          #   School コンテナ（下の containers）の隔離は Tampermonkey には効かない。
          "firefox@tampermonkey.net".permissions = [
            "alarms"
            "notifications"
            "tabs"
            "idle"
            "webNavigation"
            "webRequest"
            "webRequestBlocking"
            "unlimitedStorage"
            "storage"
            "contextMenus"
            "clipboardWrite"
            "cookies"
            "contextualIdentities"
            "downloads"
            "<all_urls>"
          ];
        };
      };

      # ── 検索エンジン（2026-09-05 に宣言化）──────────────────────────
      #
      # 宣言前の実測（search.json.mozlz4 を decode）：`defaultEngineId = "ddg"` で
      # プライベート側は未設定（通常既定に追従）、engines に Amazon / eBay / Bing /
      # perplexity / wikipedia が居残っていた。使う 3 つに絞る。
      #
      # ★ `metaData` だけ書いたエンジンは組み込み扱いになるので、Amazon や Bing を
      #   消すのに再定義は要らない（`hidden` を立てるだけ）。
      # ★ Yandex は**組み込みではない**。Firefox が app-provided で配るのは RU/TR/BY/KZ
      #   などのリージョンで、この機体は `browser.search.region = "US"`。実測でも
      #   engines に存在しなかった。よって URL テンプレートごと定義する。
      # ⚠ Yandex はロシア法の下でクエリがログされ当局への開示義務がかかる事業者。
      #   既定には据えず（default / privateDefault とも ddg）、`@y` 経由の明示的な
      #   呼び出しに限定してある。画像の逆引きと露語圏インデックスのための道具。
      # ⚠ プライベートウィンドウに別エンジンを割り当てたくなったら
      #   `browser.search.separatePrivateDefault = true` が要る（今は両方 ddg なので不要）。
      search = {
        force = true; # search.json.mozlz4 を nix 所有にする
        default = "ddg";
        privateDefault = "ddg";
        order = ["ddg" "google" "yandex"];
        engines = {
          yandex = {
            name = "Yandex";
            urls = [
              {
                template = "https://yandex.com/search/";
                params = [
                  {
                    name = "text";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = ["@y"];
          };
          bing.metaData.hidden = true;
          perplexity.metaData.hidden = true;
          wikipedia.metaData.hidden = true;
          amazondotcom-us.metaData.hidden = true;
          ebay.metaData.hidden = true;
        };
      };

      # ── コンテナ（Cookie 隔離）──────────────────────────────────────
      #
      # 私用 Google（`u/0`）と **TXST の Google Workspace**（`u/1`）を別セッションにする。
      # TXST は Microsoft（Outlook / OneDrive / SharePoint / Duo）と Google Drive の両方を
      # 出しており、後者が私用アカウントと同じ Cookie 壺に同居していた。
      #
      # ★ 割り当ては **School Space と CS4371 Drive の pin だけ**。Life / Think / Build は
      #   既定コンテナ（id 0）のままにする。私用 Gmail / Calendar を隔離しても得が無く、
      #   再ログインの手間だけ増えるため（＝分けるのは「混ざると困るもの」だけ）。
      #
      # ★ route を Google Docs / Drive に張らなかった判断とここが噛み合う：route が無い＝
      #   「今いる Space で開く」＝ School にいれば TXST の器、Life にいれば私用の器。
      #   ドキュメントが開いた文脈に付いてくる。
      #
      # ⚠ School 配下の pin には **`container = 2` を明示している**。pin は
      #   `zenDefaultUserContextId = "true"`（＝Space の既定コンテナに従う）で生成されるので
      #   理屈上は Space から継承されるはずだが、**その継承が実際に効くかは未検証**
      #   （Zen 側の実装依存）。生成 JSON 上は `userContextId = 0` のままなので、
      #   推測に賭けず明示指定に倒した。Space の器を変えるときは pin 側も併せて変えること。
      #
      # ⚠ `containersForce = true` は containers.json を nix 管理のリンクにする。
      #   現存する Firefox 既定の4つ（Personal/Work/Banking/Shopping）は消えるが、
      #   実測で**全部未使用**（どのタブも userContextId を使っていない）なので実害なし。
      # ⚠ 初回はコンテナ内で TXST に**サインインし直す**必要がある（Cookie が別なので当然）。
      #   1Password は Team ID 統合が生きているのでそのまま動く。
      containersForce = true;
      containers = {
        "TXST" = {
          id = 2;
          color = "orange";
          icon = "briefcase";
        };
      };

      # ── ★ Essentials は Space ごとではなく「コンテナごと」に共有される（2026-08-29 実測）
      #
      # 宣言上は pin が `zenWorkspace` を持つので Space 単位に見えるが、**UI 上の
      # Essentials の帯は「同じコンテナを持つ Space すべて」で共有される**。実機で確認：
      # Think（宣言上の Essential は Claude / Grok の2件）を開いた状態で帯に **8個**表示され、
      # それは全11件から School の3件（ctx=2）を引いた数と完全に一致した。
      # School の3件が見えないのは Space が違うからではなく **コンテナが違うから**。
      # 公式ドキュメントに Essentials のページは存在せず、これが一次資料。
      #
      # 帰結（設計上とても重要）：
      #   - **Space ごとに出し分けたいものを Essential にしてはいけない。** 出し分かるのは
      #     フォルダと通常 pin（こちらは `zenWorkspace` どおり Space 単位で表示される）。
      #   - 現状 ctx=0 の8件（Gmail / Calendar / Claude / Grok / GitHub / Tailscale /
      #     AtCoder / NoviSteps）は **どの Space にいても常に見えている**。
      #     ＝ Essentials は「Space の常駐」ではなく「コンテナ共通のクイックランチャ」。
      #   - Space ごとに Essentials を分けたいなら Space ごとにコンテナを割る必要があるが、
      #     コンテナごとに再ログインが要るので割に合わない（分けるのは School だけ、の判断は維持）。

      # ⚠ ここから下を宣言している間は **`darwin-rebuild switch` の前に Zen を終了**させる。
      #   activation script が zen-sessions.jsonlz4 に排他アクセスを要る。
      #
      # `spacesForce`：宣言に無い Space を削除する＝この宣言を唯一の正とする。
      # Zen の UI で作った Space は次の switch で消えるので、増やすときはここに書く。
      spacesForce = true;

      # `pinsForce` + `demote`：宣言に無い pin は**削除でなく通常タブへ降格**。
      # 既存 pin（NoviSteps / PaperCut / CS4371 Drive）の zenSyncId は Zen が振った
      # タイムスタンプ形式（例 `1783379884207-81`）で、宣言側の UUID とは照合キーが
      # 噛み合わない（session-rows.nix が `{uuid}` に brace 包みする）。force 無しだと
      # 同じ URL の pin が二重に生えるため必須。`remove` でなく `demote` にしたのは、
      # 手で足した pin を黙って消さないため（初回は上記3件が通常タブとして一度出る）。
      pinsForce = true;
      pinsForceAction = "demote";

      spaces = {
        # ── 🎓 School：直近14日の断トツ（canvas 単独で 103 ページ）
        "School" = {
          id = "a204e07c-514c-4774-a4dc-e75bf0d8d317";
          position = 1000;
          icon = "🎓";
          # この Space で開くタブは既定で TXST コンテナに入る（Space 行の containerTabId）。
          # 宣言した pin は `zenDefaultUserContextId = "true"` で生成されるので Space に従う。
          container = 2;
          theme = {
            type = "gradient";
            colors = [
              {
                red = 70;
                green = 110;
                blue = 180;
                algorithm = "floating";
                type = "explicit-lightness";
                lightness = 30;
              }
            ];
            opacity = 0.8;
            texture = 0.4;
          };
          pins = {
            "Canvas" = {
              id = "62aadd71-0419-4433-b03d-ee1a80549a02";
              url = "https://canvas.txstate.edu/";
              container = 2;
              isEssential = true;
              position = 100;
            };
            "TXST Mail" = {
              id = "54aba3fb-69d2-4a3f-8104-6743fbb03cc4";
              url = "https://outlook.cloud.microsoft/mail/";
              container = 2;
              isEssential = true;
              position = 110;
            };
            # 直近14日で 33 ページ（app.zoom.us 16 / txstate.zoom.us 4 / google.zoom.us 3）
            # ありながら、2026-08-31 の棚卸しまで**まったく宣言されていなかった**最大の穴。
            # 授業ミーティングの入口なので Essential に置く。URL は TXST テナント側
            # （`txstate.zoom.us`）にする — 実測の参加リンクが全部このホスト経由で、
            # かつ TXST SSO に乗るので TXST コンテナと噛み合う。`app.zoom.us` は
            # そこから飛ばされる Web クライアントなので入口には向かない。
            "Zoom" = {
              id = "7f49dbec-fd3d-4428-abae-03419f404a6c";
              url = "https://txstate.zoom.us/";
              container = 2;
              isEssential = true;
              position = 120;
            };
            # 学期でライフサイクルが切れるものはフォルダに落とす（Fall 2026 が終わったら
            # このフォルダごと消す。modules/domain/school/cs4355 の退役と同じ寿命）。
            #
            # ## 中身を「事務用品」から「履修科目そのもの」へ入れ替えた（2026-08-31）
            #
            # 旧構成は Printing / YuJa / Bursar ＝ **事務系**が入っていて、名前（学期）と
            # 中身（学期をまたぐ事務手続き）が噛み合っていなかった。事務は 🏫 Campus に
            # 分離し、ここは履修科目だけにする。→ 学期末は**このフォルダを消すだけ**で退役が済む。
            #
            # 科目は `places.sqlite` の Canvas コース ID から起こした（想像ではない）。
            # 直近14日の visits：
            #   2683280 CS2315                        62  ← 断トツ
            #   2740298 CS4355 Algorithms and Analysis 26
            #   1697110 CS Introduction to Linux       19
            #   2738766 CS4371 Computer Security       16
            #   2736540 CS3360 (JT)                    11
            # URL を Canvas のコース直リンクにしてあるのは、実測の踏み方がダッシュボード
            # 経由ではなく `/courses/<id>` 直行だったため（＝1クリック減る場所に置く）。
            #
            # ⚠ コース ID は**学期ごとに変わる**。次の学期はこのフォルダを作り直すので、
            #   そのとき同じクエリで採り直すこと（moz_places の url like '%/courses/%'）。
            "Fall 2026" = {
              id = "4c2d5a50-07e6-41ca-bfac-1a49eea4ff48";
              isGroup = true;
              isFolderCollapsed = true;
              folderIcon = "📚";
              position = 200;
              pins = {
                "CS2315" = {
                  id = "a17d6bfd-e9f2-4c2a-838d-bad99f3e0471";
                  url = "https://canvas.txstate.edu/courses/2683280";
                  container = 2;
                  position = 201;
                };
                "CS4355 Algorithms" = {
                  id = "d97ef5a4-4c0e-4e93-9589-87558d26ea70";
                  url = "https://canvas.txstate.edu/courses/2740298";
                  container = 2;
                  position = 202;
                };
                # 旧「zyBooks」Essential の id を引き継いでいる（新規 pin を生やさず
                # 移動として扱わせるため）。トップの汎用 `learn.zybooks.com` から
                # **CS4355 の zyBook 直リンク**に変えた：実測の zyBook は
                # `TXSTATECS4355LiFall2026` の1冊だけで、Space 全体の Essential に
                # 据えるほど汎用ではなかった。
                "CS4355 zyBook" = {
                  id = "097a76dd-54f4-4c24-8aca-31ced22f9fb0";
                  url = "https://learn.zybooks.com/zybook/TXSTATECS4355LiFall2026";
                  container = 2;
                  position = 203;
                };
                "CS4371 Computer Security" = {
                  id = "64dd7ba9-8e6b-44ed-be40-b1b3355a8545";
                  url = "https://canvas.txstate.edu/courses/2738766";
                  container = 2;
                  position = 204;
                };
                "CS3360" = {
                  id = "85f29099-cd13-4d96-942a-d36acbcad8af";
                  url = "https://canvas.txstate.edu/courses/2736540";
                  container = 2;
                  position = 205;
                };
                # コース ID の桁が他の4つ（27xxxxx）より1桁若い（1697110）＝ Fall 2026 に
                # 開講されたものではなく、**学期をまたいで生きている自習コース**と見える。
                # そうであればここではなく Campus 側が正しい。
                # ⚠ 未確認（Canvas の enrollment 期間を見ていない）。学期末に Fall 2026 を
                #   畳むとき、これだけ生きていないか確認して必要なら Campus へ移すこと。
                "Intro to Linux" = {
                  id = "6285a89c-aeb7-4462-aad2-3a14266cdb4c";
                  url = "https://canvas.txstate.edu/courses/1697110";
                  container = 2;
                  position = 206;
                };
              };
            };

            # Build から移設（2026-08-29）。判定ルール＝**成果物が誰に渡るか**：
            # CS4371 の実験環境は提出先が教授なので School。GitHub / nix は誰にも渡さない
            # 自分の道具なので Build に残す。副次的に、学期末に死ぬ塊が 📚Fall 2026 の隣に
            # 揃うので退役がフォルダ2つの削除で済む。
            "CS4371 Lab" = {
              id = "d9ea3130-2711-4faa-aad5-667036fdf6ad";
              isGroup = true;
              isFolderCollapsed = true;
              folderIcon = "🔐";
              position = 300;
              pins = {
                "pfSense Docs" = {
                  id = "2ddfd4af-f6d2-40ff-b928-213e2b3bf515";
                  url = "https://docs.netgate.com/pfsense/en/latest/";
                  container = 2;
                  position = 301;
                };
                "Kali" = {
                  id = "7189eba2-bb5e-401d-8ed6-1fb286e24a8f";
                  url = "https://www.kali.org/get-kali/";
                  container = 2;
                  position = 302;
                };
                # ★ URL から `/u/1/` を外してある。`/u/N/` は「このブラウザセッションに
                #   何番目にサインインしたか」という**相対インデックス**で、アカウントを
                #   足し引きするとズレる＝宣言に焼いてはいけない値。しかもコンテナ内は
                #   当該アカウント1つの世界なので `u/1` は解決しない。
                "CS4371 Drive" = {
                  id = "0f56ed56-e550-4d61-8310-38b8d252c632";
                  url = "https://drive.google.com/drive/folders/1ZNlHtHX9ywQPp_jGZXdLzoly4JoOYCpU";
                  container = 2;
                  position = 303;
                };
              };
            };

            # キャンパスジョブ（大学に雇われる側）。同じ判定ルールで School：
            # 成果物（労働）が渡る先は大学。加えて**入口が TXST メール**であることが
            # 履歴で確定している（2026-08-12 11:53：outlook → safelinks → Handshake）。
            #
            # ⚠ 実測に `jobs4cats` の履歴は1件も無く、実在するのは `app.joinhandshake.com`
            #   （4 visits・最終 2026-08-12）。TXST の学内求人が Handshake に載っている形と
            #   見えるが、**Jobs4Cats が別サイトとして生きているかは未確認**。
            #   別にあるなら URL をここに足す。
            # ⚠ Handshake が TXST SSO 経由かも**未確認**（履歴では SSO リダイレクトを
            #   経ずに開いており、既存セッションがあっただけの可能性）。ただし入口が
            #   TXST メールなので、どちらであっても TXST コンテナに寄せるのが一貫する。
            "Campus Job" = {
              id = "683cdeae-e7ea-4372-9efd-0e2e452506d8";
              isGroup = true;
              isFolderCollapsed = true;
              folderIcon = "💼";
              position = 400;
              pins = {
                "Handshake" = {
                  id = "9684bd67-f378-42e7-804b-97953f2c98e5";
                  url = "https://app.joinhandshake.com/";
                  container = 2;
                  position = 401;
                };
              };
            };

            # 🏫 Campus：事務・学内サービス（2026-08-31 新設）。
            #
            # **寿命で切った**：📚Fall 2026 が学期で死ぬのに対し、ここは学期をまたいで
            # 生き続けるもの。旧構成はこれらが Fall 2026 に同居していて、学期末に
            # フォルダを畳むと印刷や教科書まで巻き込んで消える形になっていた。
            #
            # Follett（大学書店）→ Kortext（電子教科書リーダー）は実測で**連鎖している**
            # （`student.follett.com/launch/krtxt/…` → `app.na1.kortext.com` → `read.…`）。
            # つまり Follett が入口で Kortext が本棚。両方置くのは重複ではなく導線の両端。
            #
            # ⚠ 旧 Fall 2026 にあった YuJa（`txst.yuja.com`）と Bursar（`secure.touchnet.com`）は
            #   削除した。どちらも `moz_places` に**行が1つも無い**＝一度も開いていない
            #   （履歴期限切れなら行だけは残るので、これは「未訪問」の確証になる）。
            #   Bursar は学期に数回しか踏まない性質上、必要になったらここへ足し直す。
            "Campus" = {
              id = "f8e9cd03-db64-48b9-9fa3-357e52569e1f";
              isGroup = true;
              isFolderCollapsed = true;
              folderIcon = "🏫";
              position = 500;
              pins = {
                "Printing" = {
                  id = "6290d0cf-7755-4be5-a813-3aac805017a8";
                  url = "https://printing.library.txstate.edu/user";
                  container = 2;
                  position = 501;
                };
                "Textbooks" = {
                  id = "764cb0b3-ecae-48db-b074-386a5733cfbe";
                  url = "https://student.follett.com/institution/texas-state-university/materials";
                  container = 2;
                  position = 502;
                };
                "Kortext" = {
                  id = "a7eac27e-3c62-4c96-bd14-0ca59b2b1df2";
                  url = "https://read.na1.kortext.com/library/books";
                  container = 2;
                  position = 503;
                };
              };
            };
          };
          # 空間内 routes は openIn を持たない（この Space に固定される）。
          routes = {
            "canvas".reference = "canvas.txstate.edu";
            # Canvas の SSO 中継（`sso.canvaslms.com`）。実測 2 ページ。Canvas 専用ホスト
            # なので School に寄せて曖昧さが無い。
            "canvaslms".reference = "canvaslms.com";
            "zybooks".reference = "zybooks.com";
            # Zoom。`app.` / `txstate.` / `google.` の3サブドメインが実測に出ていて、
            # reference を裸の `zoom.us` にすると1本で全部拾える。
            "zoom".reference = "zoom.us";
            # 教科書の導線（大学書店 → 電子教科書リーダー）。
            "follett".reference = "follett.com";
            "kortext".reference = "kortext.com";
            "txstate".reference = "txstate.edu";
            "txst".reference = "txst.edu";
            "sharepoint".reference = "txst-my.sharepoint.com";
            # 組織サイト側テナント（授業・部署の共有サイト）。txst-my は個人 OneDrive
            # テナントで別ホストなので、両方 route しないと片方が漏れる。
            "sharepoint-sites".reference = "txst.sharepoint.com";
            # onedrive.live.com は route しない（2026-08-29 監査で除去）。実測の中身は
            # CS4371 の ISO 配布（/personal/… の**個人 OneDrive 公開共有**）で、TXST の
            # 組織ドメインではない（組織側は txst-my.sharepoint.com＝上で route 済み）。
            # 個人 OneDrive を使う日が来たら School に誤って吸われるので、docs/drive と
            # 同じ「文脈に付いてくる」側に置く。授業の ISO は Canvas から踏むので
            # route 無しでも School に落ちる＝失うものは無い。
            "outlook".reference = "outlook.cloud.microsoft";
            "instructure-cdn".reference = "inscloudgate.net";
            # キャンパスジョブ。
            "handshake".reference = "joinhandshake.com";

            # ── route を張らなかったもの（2026-08-31 の棚卸しでの判断）────────────
            #
            # SSO / MFA の中継ホストは実測上位に来るが**意図的に route しない**：
            #   authentic.txstate.edu 20 / api-d64801e3.duosecurity.com 23 /
            #   login.microsoftonline.com 12 ページ（直近14日）
            # これらは単独で開くものではなく、リダイレクト連鎖の途中に現れる中継点。
            # route を張ると認証の途中で Space が切り替わる恐れがある一方、張らなければ
            # 「今いる Space に留まる」＝踏んだ文脈のまま認証が終わる（docs/drive を
            # route しない判断と同じ理屈）。なお `authentic.txstate.edu` は上の
            # `txstate.edu` に既に食われている。
            # ⚠ 未確認：Zen の route がリダイレクト先にも効くのか、最初のナビゲーション
            #   だけなのかは検証していない。効かないなら上の懸念自体が消える。
            #
            # `txst.com` も School に置かない。実測4ページの中身は Strahan Arena と
            # weight room ＝**学内スポーツ施設**で、学業ではなく生活。→ Life へ回した。
          };
        };

        # ── 🔧 Build：自分の道具箱。誰にも渡さないもの（CS4371 は School へ移設済み）
        "Build" = {
          id = "c0bd6a78-ce00-4d0e-a1e3-e6adb253db80";
          position = 2000;
          icon = "🔧";
          theme = {
            type = "gradient";
            colors = [
              {
                red = 90;
                green = 160;
                blue = 120;
                algorithm = "floating";
                type = "explicit-lightness";
                lightness = 30;
              }
            ];
            opacity = 0.8;
            texture = 0.4;
          };
          pins = {
            "nix" = {
              id = "2a3eb4c6-5bf2-452f-bcb7-7ffd4bfc146a";
              isGroup = true;
              isFolderCollapsed = true;
              folderIcon = "❄️";
              position = 300;
              pins = {
                "nixpkgs search" = {
                  id = "7355ec41-477b-4532-a61a-3f5c98cd70c9";
                  url = "https://search.nixos.org/packages";
                  position = 301;
                };
                "home-manager options" = {
                  id = "2f06174c-e6f4-4373-bd6a-5bc9cc43f028";
                  url = "https://home-manager-options.extranix.com/";
                  position = 302;
                };
              };
            };
          };
          routes = {
            "github".reference = "github.com";
            "nixos".reference = "nixos.org";
            "nix-dev".reference = "nix.dev";
            "tailscale".reference = "tailscale.com";
            "zen-browser".reference = "zen-browser.app";
            "greasyfork".reference = "greasyfork.org";
          };
        };

        # ── 🏆 Competitive Programming：整理でなく**介入**として常設する。
        #    直近14日の atcoder 訪問は 0（60日では 195）＝止まっている。真因は
        #    vault の [[strategy-design-as-avoidance]] のとおり「着手」で、Area
        #    atcoder-cyan-perf の唯一の指標は出場率（277回中23回＝8.3%）。
        #    使用実績ゼロのものに常設の場所を与えるのは通常なら悪手だが、この件に限っては
        #    サイドバーに常時見えていること自体が目的。空でも消さない。
        #    評価規約：2〜3週間でこの Space から AtCoder を一度も開かなければ「効かなかった」
        #    と判定し、それ以上 CP の周辺整備をしない（scaffolding が精進の代替になる再発防止）。
        "Competitive Programming" = {
          id = "dda5d170-5e37-4ee3-ad3a-9a7fc8ea16db";
          position = 3000;
          icon = "🏆";
          theme = {
            type = "gradient";
            colors = [
              {
                red = 190;
                green = 150;
                blue = 60;
                algorithm = "floating";
                type = "explicit-lightness";
                lightness = 30;
              }
            ];
            opacity = 0.8;
            texture = 0.4;
          };
          routes = {
            "atcoder".reference = "atcoder.jp";
            "novisteps".reference = "atcoder-novisteps.vercel.app";
          };
        };

        # ── 🧠 Think：AI と調べ物。**外部アプリから来たリンクの既定の落下先**。
        #    ★ id は既存 Space `{96b96804-…}` を再利用している。今そこに 52 タブが
        #      `zenWorkspace` で紐づいており、新しい UUID を振ると全部が宙に浮くため。
        #      「無名の何でも入る Space」＝ catch-all という意味づけもそのまま引き継ぐ。
        "Think" = {
          id = "96b96804-9df6-41c3-91f3-06b5594865ba";
          position = 4000;
          icon = "🧠";
          theme = {
            type = "gradient";
            colors = [
              {
                red = 150;
                green = 110;
                blue = 185;
                algorithm = "floating";
                type = "explicit-lightness";
                lightness = 30;
              }
            ];
            opacity = 0.8;
            texture = 0.4;
          };
          routes = {
            "claude-ai".reference = "claude.ai";
            "claude-com".reference = "claude.com";
            "grok".reference = "grok.com";
            "gemini".reference = "gemini.google.com";
            "huggingface".reference = "huggingface.co";
          };
        };

        # ── 🏠 Life：生活雑務。anjin-operations の Area とだいたい同じ守備範囲。
        "Life" = {
          id = "2c0da4d1-b250-4481-bcbc-0fc087b091db";
          position = 5000;
          icon = "🏠";
          theme = {
            type = "gradient";
            colors = [
              {
                red = 195;
                green = 105;
                blue = 95;
                algorithm = "floating";
                type = "explicit-lightness";
                lightness = 30;
              }
            ];
            opacity = 0.8;
            texture = 0.4;
          };
          pins = {
            "Accounts & Home" = {
              id = "2b12d772-5c55-45b2-9d0a-fdcc8652f8f6";
              isGroup = true;
              isFolderCollapsed = true;
              folderIcon = "🔑";
              position = 200;
              pins = {
                "Apartment" = {
                  id = "3d84205d-f811-4a87-994d-70bb7e7b065d";
                  url = "https://viewonthesquareapt.residentportal.com/";
                  position = 201;
                };
                "US Mobile" = {
                  id = "327b55a1-3e29-4f8c-a0ed-39ac12034420";
                  url = "https://app.usmobile.com/";
                  position = 202;
                };
                "Wise" = {
                  id = "f67ac324-a3b4-4ca1-b6b7-46f9f4aa0460";
                  url = "https://wise.com/";
                  position = 203;
                };
              };
            };
          };
          routes = {
            "gmail".reference = "mail.google.com";
            "gcal".reference = "calendar.google.com";
          };
        };
      };

      # 外部アプリ（メーラー・エディタ・ターミナル等）から来たリンクの既定の落下先。
      # 未分類のものは Think に集める＝「調べ物はここから始まる」を既定にする。
      spaceRouting.defaultExternalRoute = "96b96804-9df6-41c3-91f3-06b5594865ba";
    };
  };
}
