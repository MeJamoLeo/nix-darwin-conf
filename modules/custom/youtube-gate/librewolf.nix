{pkgs}:
# youtube-gate の唯一の逃げ道（システム全体 PAC を無視できる唯一のアプリ）。
#
# なぜ他のブラウザではないか：WebKit 系はプロキシ設定を上書きできない／Chromium 系は
# `--no-proxy-server` を起動フラグでしか渡せず .app の手組みが要る／Mullvad・Tor・Helium・
# Floorp・Waterfox・Zen は nixpkgs に darwin ビルドが無い／素の firefox 系は uBO を同梱しない。
#
# なぜ pref を policy ではなく AutoConfig で入れるか：enterprise policy の `Preferences`
# allowlist に `browser.privatebrowsing.autostart` が無く、両 pref を lock できるのは lockPref だけ。
# 拡張のほうは逆に policy でしか入らないので、下の extraPolicies と併用している。
#
# キャッシュ非保存（Firefox Focus 相当）は LibreWolf 既定＋下の autostart で足りている：
# `browser.cache.disk.enable=false` と `privacy.sanitize.sanitizeOnShutdown=true` が
# 上流の mozilla.cfg に入っている（153.0 で確認）。ここに足す pref は無い。
pkgs.librewolf.override {
  extraPrefs = ''
    // ⚠ この行を消すと逃げ道が黙って死ぬ。Firefox 系の既定は 5（システムのプロキシ設定に
    //   追従）＝ darwin.nix の PAC に従って YouTube が見られなくなる。
    lockPref("network.proxy.type", 0);
    // ⚠ 切るとログイン状態が残り、おすすめ・再生履歴・アルゴリズムが育ち始める
    //   （この逃げ道が「使い捨て」である根拠がこの1行）。
    lockPref("browser.privatebrowsing.autostart", true);
  '';

  # ⚠ nixExtensions に乗り換えるな。あれは `ExtensionSettings."*"` を
  #   `installation_mode = "blocked"` で塗るので、LibreWolf が同じ経路で入れている
  #   **uBlock Origin が黙って消える**（uBO はビルドに同梱されておらず、上流 policies.json の
  #   install_url で AMO から取得される。ここと全く同じ仕組み）。
  #
  # ⚠ 広告ブロッカーをここに足すな。uBlock Origin は上流が同じ経路で入れており
  #   （自動更新・プライベート許可まで込み）、AdGuard 等を重ねるとフィルタが二重適用されて
  #   ページが壊れる。ブロッカーは uBO に固定した（2026-08-03）。
  #
  # ここが上流の policies.json を壊さない根拠：wrapper は
  # `jq -s '.[0] * .[1]'` で合成する＝**再帰マージ**なので、ExtensionSettings は
  # キー単位で足し算になる（uBO や検索エンジンの blocked は残り、下のエントリが増えるだけ）。
  extraPolicies.ExtensionSettings = let
    # AMO の "latest" を指すので自動更新される（＝ nix 側にバージョンもハッシュも持たない）。
    # slug は AMO API で実測した値。GUID 形式の id を URL に入れると波括弧のエスケープが
    # 要るので、ここは slug で引く。
    fromAMO = slug: {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
      installation_mode = "normal_installed";
      # ⚠ 落とすと**拡張が丸ごと効かなくなる**。上の autostart で全ウィンドウが
      #   プライベートになるが、拡張はプライベートでは既定で無効だから。
      #   このキーは Firefox 136+ / ESR 128.8+ の機能（LibreWolf 153 なので可）。
      private_browsing = true;
    };
  in {
    # YouTube のおすすめ・Shorts・コメントを消す。この逃げ道の主目的。
    "myallychou@gmail.com" = fromAMO "youtube-recommended-videos";
    # キーボード操作（Zen 側にも入れてある）。
    "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = fromAMO "vimium-ff";
    # 再生速度の細かい制御。⚠ 上流は 2021-04 から更新が無い＝壊れたら代替を探す側。
    "{7be2ba16-0f1e-4d93-9ebc-5164397477a9}" = fromAMO "videospeed";
  };
}
