{
  config,
  pkgs,
  lib,
  ...
}: let
  ##########################################################################
  #
  #  Karabiner-Elements — Option+HJKL を Option+矢印へ変換するためだけに入れている。
  #
  #  ★ なぜ要るのか（2026-10-27 の実測が根拠）
  #
  #    macOS は **Secure Input が有効な間、`Option` および `Option+Shift` ＋
  #    英字・数字・記号 のショートカットをブロックする**（キーは前面アプリに
  #    文字として渡る）。`Option+矢印` と `Control`/`Command` 入りは通る。
  #    OmniWM 上流 #788 で作者が特定し、#808 で「どのアプリでも上書き不可」と明記。
  #
  #    実測（ogasawara / macOS 26.3.1 / OmniWM 0.7.6）:
  #      Ghostty の Secure Keyboard Entry を ON（`ioreg … kCGSSessionSecureInputPID` = 2）
  #        `Option+O`（Overview・Option+英字）        → **効かない**
  #        `Option+←`（仮割当・Option+矢印）          → **効く**
  #      予想通りの結果。仮説ではなく実測。
  #
  #    ★ Ghostty は `macos-auto-secure-input = true` が既定なので、パスワード入力を
  #      検出するたびに勝手に Secure Input を ON にする。つまりこれは稀な事故ではなく
  #      **日常的に踏んでいる**。発見時点で OmniWM 側の割当 89 件のうち 46 件が
  #      この条件に該当した（対処後は 97 件中 42 件。内訳と数え方は
  #      modules/apps/omniwm/settings.nix の差分18 を参照）。
  #
  #  ★ なぜ OmniWM 単体で解決できないのか
  #
  #    OmniWM は **1 アクション = 1 キー**。`HotkeyTrigger` が
  #    `unassigned | chord(KeyBinding) | mouseButton` で、`KeyBinding` は単一 keyCode。
  #    同じ id を2行書いても `HotkeyBindingRegistry` の
  #    `uniquingKeysWith: { first, _ in first }` で先着1個に潰れる。
  #    上流 #808（2026-10-07）で「意図的に1対1へ単純化した。戻さない」と
  #    NOT_PLANNED で閉じており、作者自身が代替として Karabiner を案内している。
  #
  #  ★ 変換の向きを間違えないこと
  #
  #      hjkl → 矢印   ✅ これ。window server に届くのが `Opt+矢印` なのでブロックされない
  #      矢印 → hjkl   ❌ 変換後に `Opt+H` が届くので**ブロックは回避できない**
  #
  #    OmniWM 側は `focus.*` を **`Option+矢印`** に割り当てる（omniwm/settings.nix の差分18）。
  #    指は hjkl のまま、物理矢印も同じく効く＝ niri の「全段で矢印と hjkl がエイリアス」に
  #    この段だけ近づく。
  #
  #  ★ Option 単独段だけに絞る理由
  #
  #    `optional: ["any"]` を付けると全修飾段で hjkl→矢印 になり、
  #    `Control+Option+H`（moveColumn.left）まで `Control+Option+←`（move.left）に
  #    化けて**全バインドの引っ越し**になる。`optional` を書かなければ
  #    「Option **だけ**が押されているとき」に限定される（他の修飾キーが乗ると不一致）。
  #    よって Control+Option 段・Option+Shift 段は hjkl のまま無傷。
  #
  #  🔴 代償：**macOS の `Option+←/→`（単語単位のカーソル移動）と
  #    `Option+↑/↓`（段落の先頭/末尾）が全アプリで効かなくなる。**
  #    OmniWM がグローバルホットキーとして食うため。これは Karabiner の有無に関係なく
  #    「focus を Option+矢印 に置く」時点で発生する。元に戻すには settings.nix の
  #    差分18 を戻すこと。
  #
  #  ⚠ 宣言できないもの（初回だけ手動）
  #    - **Driver Extension の承認**：システム設定 > 一般 > ログイン項目と機能拡張 >
  #      ドライバ機能拡張 で `Karabiner-VirtualHIDDevice` を ON にする。
  #    - **入力監視の許可**：`karabiner_grabber` と `Karabiner-Elements`。
  #    承認が済むまで `Option+HJKL` は無反応になる（物理矢印は OmniWM 側の割当で
  #    即座に効くので、完全に詰むことはない）。
  #
  #  ⚠ **ログイン項目には入れないこと**（設定ウィンドウが毎回開く原因）。
  #    本体は `/Library/LaunchAgents/org.pqrs.*` が起動するので、
  #    システム設定 > 一般 > ログイン項目 の「ログイン時に開く」に
  #    `Karabiner-Elements` を入れる必要は**無い**。入れると起動のたびに
  #    設定ウィンドウが前面に出る（公式 troubleshooting
  #    「Settings window is shown at login」が明記）。
  #    ★ 同じ画面の「バックグラウンドでの実行を許可」は**切らない**。
  #      これは動作に必須だと公式が警告している。こちらは SMAppService 管理で、
  #      private DB に入るため宣言できない（触らないので問題にならない）。
  #    ★ **「ログイン時に開く」の方は宣言で固定できる。** こちらは SMAppService では
  #      なく従来の Shared File List で、`System Events` 経由で読み書きできる
  #      （実測：`get the name of every login item` が Raycast 等を返す）。
  #      下の activation が switch のたびに「居たら消す」を流す。冪等で、
  #      存在しない項目を消してもエラーにならないことも実測済み。
  #    ※ 16.1.0 で「古い形式の既定設定だと設定ウィンドウがログイン時に開く」不具合が
  #      別途修正済み。cask は 16.3.0 なのでこちらは該当しない。
  #
  #  ⚠ ogasawara 限定で入れている（hosts/ogasawara.nix の cask）。
  #    tanegashima（MacBook Air＝内蔵キーボード）に広げる前に macOS の版を確認すること。
  #    macOS 26.4 で DriverKit の仮想 HID が**内蔵キーボードを掴めなくなる**報告がある
  #    （Karabiner #4402・Apple Developer Forums thread 817003）。#4402 自体は closed だが、
  #    26.4 で Driver Extension を有効化できない報告が別途続いている。
  #    ogasawara は 26.3.1 かつ Mac mini（外付けキーボード）なので対象外。
  #
  #  ⚠ パッケージは **cask 16.3.0**（nixpkgs は 15.7.0）。macOS 26.x の
  #    ドライバ周りは新しいほど安全なので版の新しい方を採る。
  #
  ##########################################################################
  #
  #  設定（~/.config/karabiner/karabiner.json）
  #
  #  ★ omniwm と同じく **activation で実ファイルを書く**。Karabiner も GUI 保存で
  #    この1ファイルを丸ごと書き戻すので、read-only な /nix/store symlink を置くと
  #    書き込みに失敗する。宣言が正・GUI の編集は次の switch で消える、という契約。
  #    ⚠ Karabiner は起動時に不足フィールドを既定値で補って書き戻すので、
  #      ディスク上のファイルはここで宣言した内容より大きくなる。差分ではなく
  #      「宣言した分は必ずこうなる」と読むこと。
  #  ★ karabiner_console_user_server がファイルを watch していて**自動で再読込する**
  #    ので、switch 後にアプリの再起動は要らない。
  #
  ##########################################################################
  dirKeys = [
    {
      from = "h";
      to = "left_arrow";
    }
    {
      from = "j";
      to = "down_arrow";
    }
    {
      from = "k";
      to = "up_arrow";
    }
    {
      from = "l";
      to = "right_arrow";
    }
  ];

  karabinerConfig = {
    global = {
      check_for_updates_on_startup = false; # cask 管理なのでアプリ側の更新確認は切る
      show_in_menu_bar = true;
    };

    profiles = [
      {
        name = "nix";
        selected = true;
        # ⚠ **ANSI 固定**。JIS キーボードを繋ぐなら "jis" にする必要がある
        #   （矢印変換そのものには効かないが、他の仮想キーの対応が崩れる）。
        #   ogasawara の BT5.0 KB は ANSI 配列なのでこのままでよい。
        virtual_hid_keyboard.keyboard_type_v2 = "ansi";
        simple_modifications = [];

        # 🔴 **掴むデバイスを明示する。** 既定のままだと BT5.0 KB は無視される。
        #   このキーボードは `is_keyboard` と **`is_pointing_device` の両方**を
        #   立てて自己申告するので（実測）、Karabiner がポインティングデバイス側と
        #   見なして grab しない。実際 `devices = []` のときに grab されていたのは
        #   "Apple Internal Touch Bar"（vendor 1452 / product 34304）だけで、
        #   打鍵しているキーボードは素通りしていた。
        #
        #   ⚠ **機体固有の層**（omniwm の monitorDisplayUUID と同じ性質）。
        #     vendor_id / product_id は実機から採る：
        #       "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" \
        #         --list-connected-devices
        #     掴めているかの確認は /var/log/karabiner/core_service.log の
        #     "hid device events monitor is started (grabbed)" を見る。
        #     このモジュールは ogasawara 限定なのでベタ書きで持つ。
        devices = [
          {
            identifiers = {
              is_keyboard = true;
              is_pointing_device = true;
              vendor_id = 13652; # BT5.0 KB (Bluetooth Low Energy)
              product_id = 64007;
            };
            ignore = false;
          }
        ];

        complex_modifications.rules = [
          {
            description = "Option+HJKL → Option+矢印（OmniWM focus / Secure Input 対策）";
            # ⚠ `conditions`（frontmost_application 等）は**付けていない**＝全アプリで変換する。
            #   OmniWM が止まっている間は `Option+HJKL` が macOS の単語/段落移動になる。
            #   OmniWM が動いている間はそれをグローバルに食うので差は出ない。
            #   アプリ単位で切りたくなったらここに conditions を足す。
            manipulators =
              map (k: {
                type = "basic";
                # `optional` を書かない＝ Option **だけ**のときに限定。
                # Control+Option+H などは一致せずそのまま通る。
                from = {
                  key_code = k.from;
                  modifiers.mandatory = ["option"];
                };
                to = [
                  {
                    key_code = k.to;
                    modifiers = ["left_option"];
                  }
                ];
              })
              dirKeys;
          }
        ];
      }
    ];
  };

  configFile = (pkgs.formats.json {}).generate "karabiner.json" karabinerConfig;
in {
  # ⚠ **同一ディレクトリに書いてから mv する**（install だけだと非原子的）。
  #   Karabiner はこのファイルを監視して即リロードするので、書き込み途中の
  #   中途半端な JSON を読まれうる。rename(2) なら読み手は旧か新のどちらかだけを見る。
  home.activation.karabinerSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run mkdir -p "${config.xdg.configHome}/karabiner"
    run install -m 0644 ${configFile} "${config.xdg.configHome}/karabiner/.karabiner.json.new"
    run mv -f "${config.xdg.configHome}/karabiner/.karabiner.json.new" \
      "${config.xdg.configHome}/karabiner/karabiner.json"
  '';

  # 「ログイン時に開く」に Karabiner-Elements を**入れさせない**。
  # 入っていると起動のたびに設定ウィンドウが前面に出る（公式 troubleshooting）。
  # 本体は /Library/LaunchAgents/org.pqrs.* が起動するのでログイン項目は不要。
  # ⚠ **失敗しても switch を止めない**。System Events の自動化許可（TCC）が無い文脈で
  #   activation が走ると osascript が落ちるので `|| echo` で吸収する。
  # ⚠ **timeout 20 を噛ませてある。** 許可が無いと TCC のプロンプトが出て、
  #   誰も押さないまま AppleEvent のタイムアウト（既定で約2分）まで**ハングする**。
  #   `|| echo` は失敗は拾えてもハングは拾えない。毎回の switch で走るので上限が要る。
  #   許可が無い場合は手で外すことになるので、失敗時はその旨を出す。
  home.activation.karabinerNoLoginItem = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${pkgs.coreutils}/bin/timeout 20 /usr/bin/osascript -e 'tell application "System Events"' -e 'if exists login item "Karabiner-Elements" then delete login item "Karabiner-Elements"' -e 'end tell' || echo "karabiner: ログイン項目を確認できなかった（System Events の自動化許可を確認。システム設定 > 一般 > ログイン項目 から手で外す）"
  '';
}
