{
  config,
  pkgs,
  ...
}: {
  ##########################################################################
  #
  #  REA (Reverse Engineer Anything) — エージェントに逆アセンブラを持たせる
  #  CLI ＋ MCP サーバ。npm `rea-agents`（MIT・github.com/morluto/rea）。
  #
  #  ## なぜ nix で固定しないか（2026-10-25 の判断）
  #
  #  nixpkgs に attr が無く（`rea` / `rea-agents` どちらも無し）、版が日単位で動く
  #  （6.7.0 が 10-18、6.8.0 が 10-25 09:07 公開）。buildNpmPackage で抱えると
  #  `npmDepsHash` を手で上げる係ができるだけで、claude-code 本体や claude
  #  プラグインと同じ「rev 固定＝放置すると永久に止まる」罠に入る。
  #  → 本体は **npm global ＋ `rea update`** 運用にし、宣言外の可変状態を1つ許す。
  #    このモジュールが宣言するのは、その運用が成立するための環境だけ：
  #      ① npm の global prefix を書ける場所に逃がす
  #      ② 解析エンジン（Ghidra）と JDK、その在り処
  #
  #  ## 手で1回やること（新機体セットアップ）
  #
  #    npm install -g rea-agents        # ~/.local/lib/node_modules に入る
  #    rea setup --client claude_code   # MCP 登録 ＋ skill 配置
  #    rea doctor                       # 残った ✗ を潰す
  #
  #  ★ `rea setup` の書き込み先 ~/.claude.json と ~/.claude/skills/ は HM 非所有の
  #    可変ファイル（modules/apps/claude/plugins.nix の判断と同じ）なので**他機には
  #    飛ばない**。機体ごとに1回踏む。`--scope project`（repo に .mcp.json を置く形）は
  #    upstream が非推奨にしているので使わない。
  #
  #  ## Node の版（2026-10-25 実測）
  #
  #  6.8.0 の engines は `^22.23.4 || ^24.22.1 || >=26.12.1`。手元の nodejs は 24.21.0 で
  #  これを満たさないため、npm は自動で**6.7.0（engines を満たす最新）に落として**入れる。
  #  `rea doctor` の node チェックは 24.21.0 を healthy と判定するので実害は無い。
  #  nixpkgs が node 24.22+ を取り込めば `rea update` で 6.8 系に上がる。
  #
  #  ★ ここで nodejs_26（26.12.1）や nodejs_22（22.23.4）に上げれば engines は満たせるが、
  #    どちらも aarch64-darwin のバイナリキャッシュに**無く**（nodejs-slim は fetch できる
  #    のに nodejs-XX.drv 自体がビルド対象）、1行の宣言に見えて数十分の compile を
  #    全機に強制する。上流が node 24 を上げるのを待つほうが安い、と判断した。
  #    判断の前提が変わる条件＝REA 側が 6.8+ でしか動かない機能を必要としたとき。
  #
  #  ## 既知の穴 1：GUI 起動の MCP には env が届かない
  #
  #  下の home.sessionVariables は hm-session-vars を読むシェルでしか効かない。
  #  ログインシェルを経ずに（GUI / launchd から）起動された Claude Code の MCP は
  #  GHIDRA_INSTALL_DIR / JAVA_HOME を見ない。ターミナルから起動している限り問題ない。
  #  もし GUI 起動側で `rea doctor` の ghidra が落ちたら、`rea setup` が書く
  #  ~/.claude.json の MCP 登録に env ブロックを足して明示する。
  #
  #  ## 既知の穴 2：frida の install script
  #
  #  依存の frida@17.23.2 は install script を持つが npm が既定でブロックする
  #  （`npm warn install-scripts`）。ランタイム計装系の機能はここが未実行だと動かない。
  #  許可は「任意コードを実行させる」判断なので宣言では踏まない。必要になったときに
  #  `npm install -g --allow-scripts=frida` を手で打つ。
  #
  ##########################################################################

  home.sessionVariables = {
    # npm の global prefix は既定で nodejs の store パス（read-only）＝ `npm i -g` が必ず落ちる。
    # ~/.local に逃がす。bin は modules/apps/shell/home.nix が PATH に入れている ~/.local/bin。
    NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.local";

    # REA は Ghidra 12.1.x の**展開済みディレクトリ**を要求する（相対パスは拒否される）。
    # nixpkgs の配置は $out/lib/ghidra（$out/bin/ghidra は ghidraRun への symlink）。
    GHIDRA_INSTALL_DIR = "${pkgs.ghidra}/lib/ghidra";

    # macOS の /usr/bin/java は JDK 不在のスタブ（実測: "Unable to locate a Java Runtime"）。
    # REA は analyzeHeadless を自分で起動するので JAVA_HOME を明示する。
    JAVA_HOME = pkgs.openjdk21.home;
  };

  home.packages = [
    # 12.1.4 = REA が要求する 12.1.x。
    #
    # ★ `ghidra-bin`（公式配布 zip）ではなく **`ghidra`（nixpkgs のソースビルド）**。
    #   配布 zip はネイティブの decompiler を linux_x86_64 / win_x86_64 の2つしか
    #   同梱しておらず、mac 向けは**1つも入っていない**（upstream は support/buildNatives を
    #   自分で叩かせる設計）。実測で `rea doctor` が
    #     ghidra-native_decompiler: Matching native decompiler for darwin/arm64 was not found
    #   を出した。`ghidra` のほうは os/mac_arm_64/{decompile,sleigh} を持つ。
    #   どちらもバイナリキャッシュに居る（約530MiB fetch）のでビルド時間の差は無い。
    pkgs.ghidra

    # Ghidra 12.1 の要求（nixpkgs も openjdk21 で wrap している）。
    pkgs.openjdk21
  ];
}
