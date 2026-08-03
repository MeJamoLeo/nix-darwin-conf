{pkgs, ...}:
# youtube-gate（ユーザー層）— 既定ブラウザ Zen への二重掛けだけ。
#
# なぜシステム全体 PAC（darwin.nix）だけで済ませないか：あちらは PAC 配布デーモンが落ちると
# macOS が DIRECT にフォールバックする＝ fail-open。日常の入口である Zen は独立経路で塞ぐ。
#
# なぜ policies.json ではないか：Zen は macOS の Managed Preferences を読まず
# （zen-browser/desktop#12363）、policies.json は Zen.app 内に置くとコード署名が壊れる。
# user.js なら profile 内で完結する。file:// PAC が使えるのは Firefox 系の仕様（macOS 側は廃止済み）。
#
# 撤去しても prefs.js に pref が焼き付いて残る。Zen の設定 → ネットワーク設定 →
# 「プロキシを使用しない」に戻すか、user.js を type 0 で1回書いてから外すこと。
let
  pac = import ./pac.nix {inherit pkgs;};

  # ⚠ Zen を作り直すとプロファイル ID が変わり、この行が古い ID を指したまま**黙って効かなくなる**
  #   （home.file はディレクトリごと作ってしまうので気づけない）。profiles.ini の
  #   [Install…] Default が指す側に合わせること。
  zenProfileDir = "Library/Application Support/zen/Profiles/tbq2aiii.Default (release)";
in {
  # user.js は毎起動読まれる＝ UI から変えても再起動で戻る（恒久解除ができない）。
  home.file."${zenProfileDir}/user.js".text = ''
    // managed by nix-darwin: modules/custom/youtube-gate/home.nix
    // 手で編集しても次の darwin-rebuild で上書きされる。
    user_pref("network.proxy.type", 2);
    user_pref("network.proxy.autoconfig_url", "file://${pac}");
  '';
}
