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
    rebuildfm = "fm rebuild";
    skfm = "fm skrillex"; # Skrillex を YouTube で検索し、7 分未満を 30 本集めて順不同に（結果は ~/.cache/fm に保存して使い回す。--refresh で検索し直す）
  };
}
