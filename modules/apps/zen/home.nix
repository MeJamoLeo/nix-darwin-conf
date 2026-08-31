{...}:
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
# ⚠ この値は `~/Library/Application Support/zen/profiles.ini` の `[Install…] Default`
#   と一致していなければならない。Zen 側でプロファイルを作り直したらここを更新する。
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
#   [DFEDCF58DA149FC0]                              ← nix 版 Zen のインストールハッシュ
#   Default=Profiles/tof5kg3s.Default (release)-1   ← ここを既存プロファイルにする
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
# container（Cookie 隔離）は **School だけに使う**。当初は「不要」と判断していた——実測で
# 既定コンテナ4つ（Personal/Work/Banking/Shopping）が全部未使用、Google も第1アカウント 184
# に対し第2（`/u/1/`）は 14 visits で Drive 閲覧のみ、かつ TXST 本体は Microsoft だったため。
# **その `/u/1/` が TXST の Google Workspace だと判明して反転**（本人確認・2026-08-29）。
# 私用 Google と学校 Google が同じ Cookie 壺に同居していたので、School を別の器に分ける。
{
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
      name = "Default (release)-1";
      path = "tof5kg3s.Default (release)-1";
      isDefault = true;

      # user.js の中身は関心事ごとに各モジュールが寄せる（nix の attrset マージ）：
      #   - modules/custom/youtube-gate/home.nix … PAC による YouTube 遮断
      # ここには Zen 固有の一般設定だけを置く。
      settings = {
        # 既定ブラウザ確認のダイアログを出さない（既定は macOS 側で管理する）。
        "browser.shell.checkDefaultBrowser" = false;
        # Space を切り替えたとき、前回そこで見ていたタブに戻る（区画の記憶）。
        "zen.workspaces.continue-where-left-off" = true;
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
            "zyBooks" = {
              id = "097a76dd-54f4-4c24-8aca-31ced22f9fb0";
              url = "https://learn.zybooks.com/";
              container = 2;
              isEssential = true;
              position = 110;
            };
            "TXST Mail" = {
              id = "54aba3fb-69d2-4a3f-8104-6743fbb03cc4";
              url = "https://outlook.cloud.microsoft/mail/";
              container = 2;
              isEssential = true;
              position = 120;
            };
            # 学期でライフサイクルが切れるものはフォルダに落とす（Fall 2026 が終わったら
            # このフォルダごと消す。modules/domain/school/cs4355 の退役と同じ寿命）。
            "Fall 2026" = {
              id = "4c2d5a50-07e6-41ca-bfac-1a49eea4ff48";
              isGroup = true;
              isFolderCollapsed = true;
              folderIcon = "📚";
              position = 200;
              pins = {
                "Printing" = {
                  id = "6290d0cf-7755-4be5-a813-3aac805017a8";
                  url = "https://printing.library.txstate.edu/user";
                  container = 2;
                  position = 201;
                };
                "YuJa" = {
                  id = "aa1f66f3-9117-484c-95b1-44f32ef09c88";
                  url = "https://txst.yuja.com/";
                  container = 2;
                  position = 202;
                };
                "Bursar" = {
                  id = "b2b89406-8ef6-4853-9c00-96b9f1fca070";
                  url = "https://secure.touchnet.com/";
                  container = 2;
                  position = 203;
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
          };
          # 空間内 routes は openIn を持たない（この Space に固定される）。
          routes = {
            "canvas".reference = "canvas.txstate.edu";
            "zybooks".reference = "zybooks.com";
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
            # CS4371 Lab の移設に伴い Build から移動。
            "netgate".reference = "netgate.com";
            "pfsense".reference = "pfsense.org";
            "kali".reference = "kali.org";
            "ubuntu".reference = "ubuntu.com";
            # キャンパスジョブ。
            "handshake".reference = "joinhandshake.com";
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
            # ⚠ `docs.google.com` / `drive.google.com` は**意図的に route を張らない**。
            #   実測では直近14日で docs 49・drive 16 ページと多いが、**学業と私事の両方で
            #   使われていて振り分け先が一意に決まらない**（TXST 本体は Microsoft 側＝
            #   Outlook/OneDrive/SharePoint だが、CS4371 の教材配布は Google Drive）。
            #   route が無ければ「今いる Space に開く」＝ドキュメントは開いた文脈に付いてくる
            #   という、この場合いちばん正しい既定になる。
            "apartment".reference = "viewonthesquareapt.residentportal.com";
            "petscreening".reference = "petscreening.com";
            "usmobile".reference = "usmobile.com";
            "wise".reference = "wise.com";
            "amazon".reference = "amazon.com";
            "zipair".reference = "zipair.net";
            "evaair".reference = "evaair.com";
          };
        };
      };

      # 外部アプリ（メーラー・エディタ・ターミナル等）から来たリンクの既定の落下先。
      # 未分類のものは Think に集める＝「調べ物はここから始まる」を既定にする。
      spaceRouting.defaultExternalRoute = "96b96804-9df6-41c3-91f3-06b5594865ba";
    };
  };
}
