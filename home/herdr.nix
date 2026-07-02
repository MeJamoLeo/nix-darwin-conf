# herdr（tmux ライクな AI 対応ターミナルマルチプレクサ）の設定を宣言的に管理。
# 本体は home/core.nix で導入済み（flake overlay 由来の pkgs.herdr）。
# 専用の home-manager モジュールが無いので、TOML を pkgs.formats.toml で生成して
# ~/.config/herdr/config.toml に配置する。設定は tmux.nix を参考に揃える（[[tmux.nix]]）。
#
# 注意: この config.toml は nix store への read-only symlink になるため、herdr 自身の
# 設定書換コマンド（`herdr config reset-keys` 等）は無効。設定は今後この nix で編集する。
# 変更の反映は switch 後に `herdr server reload-config`（or herdr 再起動）。
{pkgs, ...}: let
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
    };

    # 新 pane/tab は現在の作業ディレクトリを継承（tmux: split-window -c "#{pane_current_path}"）
    terminal.new_cwd = "follow";
  };
}
