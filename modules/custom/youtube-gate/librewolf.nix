{
  pkgs,
  pac,
  gate,
}:
# 履歴を残さない使い捨てブラウザ。
#
# ## 2026-10-28：「YouTube の唯一の逃げ道」をやめた
#
# 旧構成は `lockPref("network.proxy.type", 0)` でシステムの PAC を無視させ、YouTube を見るための
# 抜け道にしていた。YouTube を見すぎるので抜け道は塞ぎ、LibreWolf は「さっと調べて閉じたら
# 何も残らない」ブラウザとして残す。gate（youtube-gate の enable）が true の間は、Zen と同じく
# PAC ファイルを直接読ませる（システムの PAC 配布サーバが落ちても効く。lockPref なので
# about:config からも外せない）。YouTube 用の拡張（おすすめ消し・再生速度）も外した。
#
# なぜ LibreWolf か（他のブラウザではないか）：WebKit 系はプロキシ設定を上書きできない／
# Mullvad・Tor・Helium・Floorp・Waterfox・Zen は nixpkgs に darwin ビルドが無い／
# 素の firefox 系は uBO を同梱しない。
#
# なぜ pref を policy ではなく AutoConfig で入れるか：enterprise policy の `Preferences`
# allowlist に `browser.privatebrowsing.autostart` が無く、pref を lock できるのは lockPref だけ。
# 拡張のほうは逆に policy でしか入らないので、下の extraPolicies と併用している。
#
# キャッシュ非保存（Firefox Focus 相当）は LibreWolf 既定＋下の autostart で足りている：
# `browser.cache.disk.enable=false` と `privacy.sanitize.sanitizeOnShutdown=true` が
# 上流の mozilla.cfg に入っている（153.0 で確認）。ここに足す pref は無い。
pkgs.librewolf.override {
  extraPrefs =
    ''
      // ⚠ 切るとログイン状態が残り、閲覧履歴が育ち始める
      //   （このブラウザが「使い捨て」である根拠がこの1行）。
      lockPref("browser.privatebrowsing.autostart", true);
    ''
    + (
      if gate
      then ''
        // youtube-gate の柵。2 = PAC を使う。file:// の PAC は Firefox 系なら読める
        // （macOS 側は file:// PAC を廃止済み。darwin.nix のヘッダ参照）。
        lockPref("network.proxy.type", 2);
        lockPref("network.proxy.autoconfig_url", "file://${pac}");
      ''
      else ""
    );

  # 起動時に開くページ。autostart でプライベート固定でも StartPage="homepage" は効く。
  extraPolicies.Homepage = {
    URL = "https://musicforprogramming.net";
    StartPage = "homepage";
  };

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
  #
  # 2026-10-28：YouTube 用の拡張（youtube-recommended-videos・videospeed）を外した。
  # policy からキーを消すだけだと、既に入った拡張はプロファイルに残る（normal_installed は
  # 「入れる」だけで「消す」はしない）。なので "blocked" を明示して消させる
  # （blocked は「入れさせない＋入っていれば消す」）。
  extraPolicies.ExtensionSettings = let
    # AMO の "latest" を指すので自動更新される（＝ nix 側にバージョンもハッシュも持たない）。
    # slug は AMO API で実測した値。GUID 形式の id を URL に入れると波括弧のエスケープが
    # 要るので、ここは slug で引く。
    fromAMO = slug: {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
      installation_mode = "normal_installed";
      # ⚠ 落とすと**拡張が丸ごと効かなくなる**。上の autostart で全ウィンドウが
      #   プライベートになるが、拡張はプライベートでは既定で無効だから。
      #   このキーは Firefox 136+ / ESR 128.8+ の機能（LibreWolf 158 なので可）。
      private_browsing = true;
    };
  in {
    # キーボード操作（Zen 側にも入れてある）。
    "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = fromAMO "vimium-ff";
    # 外した YouTube 用の拡張。入っていれば消させる（上のコメント）。
    "myallychou@gmail.com".installation_mode = "blocked"; # youtube-recommended-videos
    "{7be2ba16-0f1e-4d93-9ebc-5164397477a9}".installation_mode = "blocked"; # videospeed
  };
}
