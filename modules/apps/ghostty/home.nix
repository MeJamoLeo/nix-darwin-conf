{
  lib,
  pkgs,
  ghostty-cursor-shaders,
  ...
}: let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in {
  programs.ghostty = {
    enable = true;
    # nixpkgs の ghostty は meta.platforms が Linux 限定（darwin 非対応・ビルド不可、
    # dejima で確認済み）。Mac の本体は Homebrew cask "ghostty" で入れ、ここは設定のみ管理。
    # x1nano（NixOS）は 2026-11-20 に kitty から乗り換え、nixpkgs の物を入れる。Linux では
    # home-manager が systemd のユーザーサービス（窓なしで常駐）も入れる＝上から降りてくる
    # 端末（下の global keybind）が、Ghostty の窓を開いていなくても出せる。
    package = if isLinux then pkgs.ghostty else null;
    settings = lib.mkMerge [ {
      # 標準 TERM を名乗る: xterm-ghostty だと terminfo の無い接続先
      # (nix の mosh・大学サーバー等)で "unknown terminal type" になるため。
      # Ghostty 固有の機能宣言を捨てるだけで 256色/truecolor は無影響
      term = "xterm-256color";
      font-size = 13;
      # theme 未指定 = Ghostty デフォルト配色。戻すなら例: theme = "Catppuccin Latte"
      # （組み込み一覧は `ghostty +list-themes`）
      background-opacity = 0.5;
      # blur はオフ（0 = 無効を明示）。有効化するなら 1 以上の整数
      # （0.1 等の小数は invalid value を実機確認済み。旧名 background-blur-radius は廃止）
      background-blur = 0;
      macos-titlebar-style = "hidden";
      # カーソルシェーダは無効化（背景透過は残したいので background-opacity は死守、shader を切る）。
      # 実測：cursor_warp.glsl + custom-shader-animation の合わせ技で WindowServer が
      # 21%＋常時貼り付きだった（Ghostty プロセス kill で -21ポイント）。opacity 経由の
      # 背景合成コストが caldash --wallpaper と組み合わさって重かった説濃厚。
      # cursor エフェクトが恋しくなったら custom-shader を1本だけ足して測定し直す。
      # 全一覧: cursor_warp / cursor_sweep / cursor_tail /
      # sonic_boom_cursor / ripple_cursor / rectangle_boom_cursor / ripple_rectangle_cursor
      # （sahaj-b/ghostty-cursor-shaders・MIT）。
      custom-shader = [];
      keybind = [
        "super+d=new_split:right"
        "super+shift+d=new_split:down"
        "super+w=close_surface"
        "super+j=goto_split:next"
        "super+ctrl+h=resize_split:left,50"
        "super+ctrl+l=resize_split:right,50"
        "super+ctrl+k=resize_split:up,50"
        "super+ctrl+j=resize_split:down,50"
      ];
    }
    # x1nano（niri）だけ：上から降りてくる端末。Mac の OmniWM の Option+` と同じ役だが、
    # niri は Mod（Super）を軸にしているので Mod+` にした（2026-11-20 本人の希望）。
    # global: は XDG portal の GlobalShortcuts 経由（niri＋xdg-desktop-portal-gnome で
    # 2026-11-20 に動くことを確認）。niri 側には同じキーを割り当てないこと。
    # キー名は backquote（grave は Ghostty が InvalidFormat で拒む）。
    (lib.mkIf isLinux {
      keybind = ["global:super+backquote=toggle_quick_terminal"];
      quick-terminal-position = "top";
      quick-terminal-size = "40%";
    })
    ];
  };

  # Linux：常駐サービスをログインと同時に起動する。home-manager はユニットを置くだけで
  # 有効にしない（2026-11-20、x1nano で inactive のままだった）。常駐が無いと
  # ・窓を開くたびに GTK の初期化から始まり 1.9 秒かかる（常駐ありの +new-window は 0.09 秒）
  # ・最初に手で開いた Ghostty がバス名を取り、後からサービスを起こしても protocol で落ちる
  # ・上から降りてくる端末（global keybind）が窓を開くまで効かない
  xdg.configFile."systemd/user/graphical-session.target.wants/app-com.mitchellh.ghostty.service" =
    lib.mkIf isLinux {
      source = "${pkgs.ghostty}/share/systemd/user/app-com.mitchellh.ghostty.service";
    };
}
