{
  config,
  pkgs,
  lib,
  ...
}: let
  ##########################################################################
  #
  #  OmniWM — Niri / Hyprland 系の macOS タイル型 WM（AeroSpace の置き換え候補）。
  #  上流 github:BarutSRB/OmniWM・GPL-2.0・Apple Developer ID 署名 + notarize 済み。
  #
  #  ★★ パッケージ部分は**繋ぎ**（2026-08-30）。nixpkgs 本体に入ったら消す。★★
  #
  #    `omniwm: init at 0.6.3` (622f9b32) が **2026-08-29 に nixpkgs master へ merge
  #    された**（pkgs/by-name/om/omniwm/package.nix・maintainers: mmfallacy, samiser）。
  #    ただし **nixpkgs-unstable / nixos-unstable チャンネルにはまだ降りていない**
  #    （実測：master には在り、両チャンネル branch には 404）。この repo の
  #    nixpkgs-darwin は nixpkgs-unstable 追従なので、今 `nix flake update` しても
  #    取れない。チャンネルが回るまでの数日を埋めるためだけにこの derivation が在る。
  #
  #    ▼ 降りてきたら（`nix eval nixpkgs#omniwm.version` が通ったら）：
  #        下の `omniwm = pkgs.stdenvNoCC.mkDerivation …` を丸ごと消して
  #        `omniwm = pkgs.omniwm;` にする。このファイルの他の部分は無変更。
  #      実装を nixpkgs 版に寄せてあるので差分は出ないはず。
  #
  #  ★ 他の入手経路を実測で潰した結果（2026-08-30）：
  #    - **上流に flake.nix は無い**（tree 1132 ファイルを走査。README の
  #      `### Nix` 節にある比較表が指すのは全部**外部**リポジトリ）。
  #    - **OmniWM 専用の flake を作っている人は居ない**。
  #    - コミュニティ実装は package が5つ（nixpkgs 公式 / DoomHammer NUR /
  #      DavSanchez / gapul / Yus314）、options 付きモジュールが4人
  #      （DavSanchez / ryoppippi / eljangus / samiser）。**flake output として
  #      公開しているのは DavSanchez の `homeModules.omniwm` だけ**。
  #    - その DavSanchez を input に取らなかった理由は下の「設定」節を参照
  #      （settings の持ち方が複数モニタ + 複数機体で破綻する）。
  #    - `services.omniwm` 相当の nix-darwin モジュールは存在しない。
  #    - homebrew tap `BarutSRB/tap` は不採用。この repo は 2026-07-08 に
  #      サードパーティ tap を2本消した経緯があり、brew は dejima に届かない。
  #
  #  ⚠ 実行要件（README + Info.plist 実測）：
  #    - **macOS 26+ (Tahoe) / Apple Silicon**（LSMinimumSystemVersion = 26.0）
  #    - **`Displays have separate Spaces` が ON**（OFF だと OmniWM は
  #      ウィンドウ管理を一時停止する）。この repo は
  #      `modules/base/macos-defaults/darwin.nix` の `spaces.spans-displays = false`
  #      で既に ON を宣言済み＝AeroSpace からの移行でログアウトは要らない。
  #    - 初回起動時に手動で許可が要る（宣言できない）：
  #      アクセシビリティ（必須）／入力監視（必須）／画面収録（任意・Overview 用）
  #
  #  更新手順（繋ぎの間に新リリースが出たら）：
  #    1. version を書き換える
  #    2. `nix store prefetch-file --name OmniWM-v<ver>.zip \
  #         https://github.com/BarutSRB/OmniWM/releases/download/v<ver>/OmniWM-v<ver>.zip`
  #       で出た SRI ハッシュを hash に貼る
  #
  ##########################################################################
  version = "0.6.4";

  omniwm = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "omniwm";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/BarutSRB/OmniWM/releases/download/v${finalAttrs.version}/OmniWM-v${finalAttrs.version}.zip";
      hash = "sha256-myv1TSDWf1NicAMuBiUXbAbG4DuIl93wJVWNlIM55ec=";
    };

    # zip の中身は OmniWM.app 1個。unpackPhase がその中へ cd するので、
    # 以降の `.` は .app の中身（Contents/）を指す。
    sourceRoot = "OmniWM.app";

    __structuredAttrs = true;
    strictDeps = true;

    # unzip ではなく bsdtar（libarchive）で展開する。nixpkgs 版と同じ判断で、
    # 理由は「unzip は .app の署名を壊す」（上流 package.nix のコメント。OmniWM の
    # README も DoomHammer 版を名指しで同じ理由で非推奨にしている）。
    # AppleDouble（._foo）も bsdtar なら残らない。
    unpackCmd = ''bsdtar -xf "$curSrc"'';

    nativeBuildInputs = [pkgs.libarchive];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/Applications/OmniWM.app"
      cp -r . "$out/Applications/OmniWM.app"

      # 本体と同梱 CLI（omniwmctl・IPC/自動化用）を PATH に出す。
      # 実体を動かすと署名が壊れるので symlink で参照する。
      mkdir -p "$out/bin"
      ln -s "$out/Applications/OmniWM.app/Contents/MacOS/OmniWM" "$out/bin/OmniWM"
      ln -s "$out/Applications/OmniWM.app/Contents/MacOS/omniwmctl" "$out/bin/omniwmctl"

      runHook postInstall
    '';

    meta = {
      description = "Niri/Hyprland 系の macOS タイル型ウィンドウマネージャ";
      homepage = "https://github.com/BarutSRB/OmniWM";
      license = pkgs.lib.licenses.gpl2Only;
      mainProgram = "OmniWM";
      platforms = ["aarch64-darwin"];
      sourceProvenance = [pkgs.lib.sourceTypes.binaryNativeCode];
    };
  });

  ##########################################################################
  #
  #  設定（~/.config/omniwm/settings.toml）
  #
  #  ★ なぜ `xdg.configFile`（＝store symlink）ではなく activation で実ファイルを
  #    書くのか。OmniWM は settings.toml を**実行時に所有する**：GUI 編集でも
  #    スキーマ移行でも丸ごと書き戻す。書けない相手（read-only な /nix/store
  #    symlink）だと、未知キーが1つあるだけで **settings.toml.corrupt に退避して
  #    既定値にフォールバックする**（eljangus/nixos のコメントが実測を書いている）。
  #    DavSanchez の `homeModules.omniwm` は `xdg.configFile` + `force = true` で、
  #    この穴を踏む。だから彼のモジュールを input に取らず、**ryoppippi と
  #    eljangus が独立に到達した「activation で書き込み可能な実ファイルを置く」**
  #    方式を採る。
  #
  #  ★ なぜ「上書き」ではなく「マージ」なのか（複数モニタ × 複数機体）。
  #    OmniWM のモニタ設定は2層に割れている：
  #      - **ロール層**（ポータブル）: `[workspaces.monitorAssignment] type =
  #        "main" / "secondary"`。UUID 非依存で、AeroSpace の
  #        `workspace-to-monitor-force-assignment` に相当する。**宣言したい層。**
  #      - **UUID 層**（機体固有）: `monitor{Bar,Dwindle,Gap,Niri,Orientation,
  #        Routing}Overrides` と `[routing] mode`。`monitorDisplayUUID` ＝
  #        **物理ディスプレイの UUID がキー**。
  #    ogasawara（Mac mini + 外部モニタ）と tanegashima（MacBook Air 内蔵のみ）は
  #    profiles/mac-workstation.nix を共有しているので、UUID 層をコミットすると
  #    **必ずどちらかで間違う**。merge-settings.nu が UUID 層だけ live 値を残す。
  #    （eljangus は UUID 層を空リストで上書きしてしまうので、GUI の Monitor
  #    Setup で並べた実机マップが switch のたびに飛ぶ。そこだけ採らない。）
  #
  #  ▼ 運用（2026-08-30 に宣言化済み。宣言が正・UUID 層だけ実機の GUI が正）：
  #    - 設定の実体は ./settings.nix。GUI で触った差分を取り込むときは、live の
  #      `~/.config/omniwm/settings.toml` と diff を取って必要な行だけ写す。
  #    - 🔴 **配列は全件書くか一切書かないかの二択**（deep-merge は record にしか
  #      再帰せず、配列はテンプレ側が丸ごと勝つ）。`hotkeys` 169件・`workspaces` 7件・
  #      `appRules` 13件はいずれも全件宣言してある。減らすと消える。
  #    - AeroSpace に戻したくなったら profiles/mac-workstation.nix の import 2行を
  #      入れ替えるだけでよい（このモジュールは settings.toml を書くのをやめ、
  #      live ファイルはそのまま残る）。
  #
  #  ⚠ nix attrset にする利点：AeroSpace 設定がやっていた
  #    `${config.home.profileDirectory}/bin/cp-go-launch`（alt-g）のような
  #    **store パス補間**がそのまま書ける。生の settings.toml を tracked file に
  #    するとこれができない（ryoppippi は生 TOML 派だが、彼はパス補間を使わない）。
  #    ⚠ ただし OmniWM のホットキーは「固定コマンド ID → binding」の対応表で、
  #    **任意コマンドを実行する ID が無い**（169 ID を全列挙して0件）。alt-g と
  #    alt-0/1/2 系5個は OmniWM 側では表現できず、別のホットキーデーモン
  #    （skhd 等）へ逃がす必要がある。逃がし先は使用実績を見てから決める。
  #
  ##########################################################################
  ##########################################################################
  #
  #  フォーカス枠は JankyBorders（AeroSpace 時代からの継続）
  #
  #  OmniWM 内蔵の borders に描画の不具合があるため、枠だけ外部デーモンに出させる。
  #  JankyBorders は WM 非依存（SkyLight でフォーカス窓を追うだけで、yabai や
  #  AeroSpace への依存は無い）なので、AeroSpace が
  #  `after-startup-command = ["exec-and-forget borders …"]` でやっていた起動を
  #  launchd に移すだけで同じ枠が出る。色と幅は AeroSpace 時代の値そのまま
  #  （modules/apps/aerospace/home.nix と一致させてある）。
  #
  #  ⚠ 併用しないこと。OmniWM 側は settings.nix で `borders.enabled = false` に
  #    してある。両方 on にすると枠が二重に出る。内蔵側が直ったらこの節と
  #    launchd.agents.jankyborders を消して settings.nix を true に戻す。
  #
  ##########################################################################
  bordersBin = "${pkgs.jankyborders}/bin/borders";

  tomlFormat = pkgs.formats.toml {};

  # 宣言する設定。{} にすると activation ごと無効化され、settings.toml は GUI 任せに戻る。
  settings = import ./settings.nix;

  settingsFile = tomlFormat.generate "omniwm-settings.toml" settings;
in {
  home.packages = [
    omniwm
    pkgs.jankyborders
  ];

  # 常駐。AeroSpace の `start-at-login = true` に相当するものが nix 経由の
  # インストールには無い（あれは LaunchServices のログイン項目登録で、.app を
  # 一度 GUI で起動しないと付かない）ので launchd で明示的に持つ。
  # DavSanchez / ryoppippi / samiser の3実装とも同じ形。
  launchd.agents.omniwm = {
    enable = true;
    config = {
      Program = "${omniwm}/Applications/OmniWM.app/Contents/MacOS/OmniWM";
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/omniwm.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/omniwm.err.log";
    };
  };

  # JankyBorders も常駐させる（AeroSpace の after-startup-command 相当）。
  # borders は前面に居続けるフォアグラウンドプロセスなので KeepAlive で持つ。
  launchd.agents.jankyborders = {
    enable = true;
    config = {
      ProgramArguments = [
        bordersBin
        "active_color=0xff6d28d9"
        "inactive_color=0x00000000"
        "width=20.0"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/jankyborders.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/jankyborders.err.log";
    };
  };

  # settings が空でない間だけ、テンプレを live ファイルへマージする。
  # merge-settings.nu は ryoppippi/dotfiles（MIT）由来。ファイル冒頭に出典と
  # ライセンス全文あり。
  home.activation = lib.optionalAttrs (settings != {}) {
    omniwmSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${lib.getExe pkgs.nushell} ${./merge-settings.nu} \
        ${settingsFile} "${config.xdg.configHome}/omniwm/settings.toml"
    '';
  };
}
