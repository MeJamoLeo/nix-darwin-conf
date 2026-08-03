{pkgs}:
# youtube-gate の唯一の逃げ道（システム全体 PAC を無視できる唯一のアプリ）。
#
# なぜ他のブラウザではないか：WebKit 系はプロキシ設定を上書きできない／Chromium 系は
# `--no-proxy-server` を起動フラグでしか渡せず .app の手組みが要る／Mullvad・Tor・Helium・
# Floorp・Waterfox・Zen は nixpkgs に darwin ビルドが無い／素の firefox 系は uBO を同梱しない。
#
# なぜ policy ではなく AutoConfig か：enterprise policy の `Preferences` allowlist に
# `browser.privatebrowsing.autostart` が無く、両 pref を lock できるのは lockPref だけ。
# uBlock Origin は LibreWolf がバンドル済み（プライベートでも有効）なので明示追加は不要。
pkgs.librewolf.override {
  extraPrefs = ''
    // ⚠ この行を消すと逃げ道が黙って死ぬ。Firefox 系の既定は 5（システムのプロキシ設定に
    //   追従）＝ darwin.nix の PAC に従って YouTube が見られなくなる。
    lockPref("network.proxy.type", 0);
    // ⚠ 切るとログイン状態が残り、おすすめ・再生履歴・アルゴリズムが育ち始める
    //   （この逃げ道が「使い捨て」である根拠がこの1行）。
    lockPref("browser.privatebrowsing.autostart", true);
  '';
}
