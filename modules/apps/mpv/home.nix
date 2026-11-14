{pkgs, ...}: {
  # mpv：ターミナルの動画・音楽プレーヤー。YouTube の URL は中で yt-dlp を呼んで再生する。
  # 2026-11-13 に claudefm（npm 製の自前ビルド）を削除して置き換えた。claudefm は mpv に
  # URL を渡して画面を付けるだけで、音を流すには mpv だけで足りるため。
  # 画面は自作の TUI（custom/fm）が受け持つ。
  #
  # YouTube の柵（custom/youtube-gate）との関係：2026-11-08 に hosts から YouTube を外した。
  # yt-dlp は PAC を読まないので通り、ブラウザは PAC で止まったまま。
  home.packages = [pkgs.mpv pkgs.yt-dlp];
}
