{pkgs, ...}: {
  programs.ghostty = {
    enable = true;
    # nixpkgs の ghostty は meta.platforms が Linux 限定（darwin 非対応・ビルド不可、
    # dejima で確認済み）。本体は Homebrew cask "ghostty" で入れ、ここは設定のみ管理。
    package = null;
    settings = {
      # 標準 TERM を名乗る: xterm-ghostty だと terminfo の無い接続先
      # (nix の mosh・大学サーバー等)で "unknown terminal type" になるため。
      # Ghostty 固有の機能宣言を捨てるだけで 256色/truecolor は無影響
      term = "xterm-256color";
      font-size = 13;
      theme = "Catppuccin Latte"; # Ghostty 組み込み(+list-themes で確認)
      background-opacity = 0.8;
      # blur はオフ（未指定＝Ghostty 既定で無効）。有効化するなら background-blur = 1
      # （整数のみ有効、0.1 は invalid value を実機確認済み。旧名 background-blur-radius は廃止）
      macos-titlebar-style = "hidden";
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
    };
  };
}
