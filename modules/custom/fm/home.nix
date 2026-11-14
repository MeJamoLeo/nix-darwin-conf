{pkgs, ...}: let
  # fm：mpv を裏で動かし、香水瓶型ウォークマン（NW-E500 系）風の画面で操作する自作 TUI。
  # Python の標準ライブラリだけで書いてある（curses と mpv の IPC ソケット）。
  # mpv と yt-dlp は apps/mpv が PATH に入れる。
  fm = pkgs.writeScriptBin "fm" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./fm.py}
  '';
in {
  home.packages = [fm];

  home.shellAliases = {
    claudefm = "fm claude"; # Claude FM（24 時間 lofi 配信）
    skfm = "fm skrillex"; # Skrillex を YouTube 検索の上位 20 本で順不同に
  };
}
