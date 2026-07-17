# herdr（tmux ライクな AI 対応ターミナルマルチプレクサ）の設定を宣言的に管理。
# 本体は modules/core-packages/home.nix で導入済み（flake overlay 由来の pkgs.herdr）。
# 専用の home-manager モジュールが無いので、TOML を pkgs.formats.toml で生成して
# ~/.config/herdr/config.toml に配置する。設定は tmux.nix を参考に揃える（[[tmux.nix]]）。
#
# 注意: この config.toml は nix store への read-only symlink になるため、herdr 自身の
# 設定書換コマンド（`herdr config reset-keys` 等）は無効。設定は今後この nix で編集する。
# 変更の反映は switch 後に `herdr server reload-config`（or herdr 再起動）。
{
  pkgs,
  config,
  ...
}: let
  toml = pkgs.formats.toml {};
in {
  xdg.configFile."herdr/config.toml".source = toml.generate "herdr-config.toml" {
    keys = {
      prefix = "ctrl+t"; # tmux: prefix = C-t（既定 C-b から変更）

      # vi 風 pane 移動（tmux: prefix + h/j/k/l = select-pane）※herdr 既定と同じだが明示
      focus_pane_left = "prefix+h";
      focus_pane_down = "prefix+j";
      focus_pane_up = "prefix+k";
      focus_pane_right = "prefix+l";

      # tab 移動: prefix + , / .（= < / > の矢印イメージ）。
      # shift+記号（< >）は端末依存で外れやすいため unshifted のキーを使う。
      # ※herdr のキー構文で named 扱いなのは minus/comma/ampersand/plus/backtick だけ。
      #   それ以外は「1文字」必須なので "." は名前(dot)でなくリテラル "." で書く
      #   （"prefix+dot" は invalid keybinding で無効化される）。
      previous_tab = "prefix+comma"; # "<"（named 形。リテラル "," でも可）
      next_tab = "prefix+."; # ">"（named 形は無いのでリテラル）

      # workspace 移動: 空いた n/p を workspace 送りに（herdr 既定は unset）。
      previous_workspace = "prefix+p";
      next_workspace = "prefix+n";

      # 分割（tmux: | = 左右 / - = 上下）。herdr は divider 向き命名の想定：
      #   split_vertical   = 縦線 = 左右（tmux の |）
      #   split_horizontal = 横線 = 上下（tmux の -、herdr 既定と一致）
      # ※ | は herdr のキー構文で扱いにくいので backslash（| の物理キー）に割当。
      #   初回起動で向き/キーを目視確認し、合わなければ prefix+v 等へ変更する。
      split_vertical = "prefix+backslash";
      split_horizontal = "prefix+minus";

      # tmux の select-layout プリセット（M-1..M-5 / prefix+Space = next-layout 相当）。
      # herdr に組み込みが無いので自前スクリプト herdr-layout（下の home.file で
      # ~/bin に配置。socket API で pane を一時 tab 経由で組み替える＝端末は生存）を叩く。
      # ※キー名が invalid だと herdr は該当バインドだけ無効化して server.log に残す。
      #   reload 後に `grep -i invalid ~/.config/herdr/herdr-server.log` で確認する。
      command = [
        {
          key = "prefix+space";
          type = "shell";
          command = "${config.home.homeDirectory}/bin/herdr-layout next";
        }
        {
          key = "prefix+alt+1";
          type = "shell";
          command = "${config.home.homeDirectory}/bin/herdr-layout even-horizontal";
        }
        {
          key = "prefix+alt+2";
          type = "shell";
          command = "${config.home.homeDirectory}/bin/herdr-layout even-vertical";
        }
        {
          key = "prefix+alt+3";
          type = "shell";
          command = "${config.home.homeDirectory}/bin/herdr-layout main-horizontal";
        }
        {
          key = "prefix+alt+4";
          type = "shell";
          command = "${config.home.homeDirectory}/bin/herdr-layout main-vertical";
        }
        {
          key = "prefix+alt+5";
          type = "shell";
          command = "${config.home.homeDirectory}/bin/herdr-layout tiled";
        }
      ];
    };

    # 新 pane/tab は現在の作業ディレクトリを継承（tmux: split-window -c "#{pane_current_path}"）
    terminal.new_cwd = "follow";

    # herdr 組み込みの Tokyo Night Day（"tokyo-day"/"tokyonight-day" も同義）。
    # Ghostty 側は Catppuccin Latte のまま（あえて不揃い）。
    # ※config.toml は nix store の read-only symlink なので UI からのテーマ変更は
    #   保存されない（herdr-server.log の config.write error はその既知の挙動）。
    theme.name = "tokyo-night-day";
  };

  # Claude Code SessionStart hook: herdr pane 内で起動した Claude に
  # workspace/tab の日本語 rename を促す（詳細はスクリプト冒頭コメント）。
  # herdr 外では HERDR_ENV 不在で無音 no-op なので、この herdr.nix を外せば
  # 挙動ごと消える。~/.claude/settings.json 側の登録は存在ガード付きの1行
  # （hook ファイルが消えても無害に空振りする）で、settings.json は Claude Code /
  # herdr integration も書き込む可変ファイルのため home-manager では所有しない。
  home.file.".claude/hooks/herdr-auto-name.sh" = {
    source = ./herdr-auto-name.sh;
    executable = true;
  };

  # tmux select-layout 相当（even-h/even-v/main-h/main-v/tiled/next）。
  # 上の keys.command から呼ぶほか、CLI からも `herdr-layout tiled` 等で使える。
  # stdlib のみの python スクリプト。shebang を nix の python3 に差し替えて hermetic に
  # する（dejima のような素の VM には /usr/bin/env python3 が無くても動くように）。
  home.file."bin/herdr-layout" = {
    text =
      builtins.replaceStrings
      ["#!/usr/bin/env python3"] ["#!${pkgs.python3}/bin/python3"]
      (builtins.readFile ./herdr-layout);
    executable = true;
  };
}
