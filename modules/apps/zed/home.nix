{...}: {
  # Zed は ~/.config/zed/settings.json を読む(JSONC 可だが toJSON の厳密 JSON で問題ない)。
  # 本体は nixpkgs の zed-editor (modules/core-packages/home.nix)。設定変更は UI からではなく
  # ここを編集して rebuild する(store への read-only symlink になるため、
  # UI のテーマピッカー等から保存しようとするとエラーになる)。
  # デフォルト一覧: コマンドパレット `zed: open default settings`
  # prompts/ と themes/ は実行時データなので管理しない。
  xdg.configFile."zed/settings.json" = {
    force = true; # 手動運用時代の settings.json が残っていても上書きする
    text = builtins.toJSON {
      # nix 管理では app bundle が read-only で self-update は成立しない。
      # 更新は flake update 経由であることを明示しておく。
      auto_update = false;

      vim_mode = true;
      session.trust_all_worktrees = true;

      # Claude Code を ACP 経由のエージェントとして使う
      agent_servers.claude-acp.type = "registry";

      # 言語拡張。Zed が起動時にレジストリから取得して
      # ~/.local/share/zed/extensions/installed/<id>/ へ入れる。そこは nix 管理外の
      # 可変領域なので、settings.json が store への read-only symlink でも成立する。
      # ID はそのディレクトリ名と同じ文字列。
      # nix 拡張は tree-sitter による syntax highlighting を提供する。LSP（nil / nixd）は
      # 含まれないので、補完や定義ジャンプが要るなら別途 home.packages に置いて
      # lsp / language_servers で指名する。今は入れていない。
      auto_install_extensions.nix = true;

      # C/C++ — clangd の実体は pkgs.clang-tools（今は modules/domain/school/cs4355/home.nix
      # が供給）。Zed は PATH 上の clangd を見つけて引数なしで起動する。
      #
      # ⚠️ nixpkgs の clangd は macOS で **libc++ を二重に** include path へ入れる。
      #    自前の /nix/store/...-libcxx-*/include/c++/v1 と、-isysroot 経由の
      #    Xcode SDK の usr/include/c++/v1 が両方載り、<vector> や <type_traits> の
      #    パースが途中で死ぬ。症状は「ファイル全体が赤い ＋ std:: の補完がゼロ」——
      #    標準ヘッダが壊れると clangd が std のシンボルを1つも持てないので、
      #    赤線と補完不能は同じ1つの原因。
      #
      #    2026-09-10 実測（zylab1 の main.cpp・clangd --check のエラー数）:
      #      素の nix clangd                              5 errors
      #      + --query-driver=<実コンパイラ>              0 errors
      #      Xcode 付属の clangd（/usr/bin/clangd）        0 errors
      #
      # --query-driver は「clangd がシステム include を訊きに行ってよいドライバ」の
      # ホワイトリスト。実コンパイラに訊いた結果が優先されるので二重載せが解消する。
      #
      # ★マッチ対象は **compile_commands.json に書いてある文字列そのもの**で、symlink を
      #   解決した後のパスではない（実測：DB に /etc/profiles/... と書いて glob を
      #   /nix/store/*/bin/g++ だけにすると効かず 7 errors）。だから
      #   「安定パス」と「store 実体」の両方を許可しておく。
      #
      # g++ を並べているのは CS4355 の都合。採点環境（zyLab = Linux + g++ + libstdc++）に
      # エディタの見え方を寄せるため、DB 側で g++ を名指ししている
      # （modules/domain/school/cs4355/home.nix の compile_commands.json 種）。
      # clang* を残すのは ZYG_SAN=1 のときと、DB の無い場所での素の C++ のため。
      lsp.clangd.binary.arguments = [
        "--query-driver=/etc/profiles/per-user/*/bin/g++,/nix/store/*/bin/g++,/usr/bin/clang*"
      ];

      icon_theme = "Zed (Default)";
      ui_font_size = 16;
      buffer_font_size = 15;
      theme = {
        mode = "dark";
        light = "Ayu Light";
        dark = "One Dark";
      };
    };
  };
}
