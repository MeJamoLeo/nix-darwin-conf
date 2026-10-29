{
  pkgs,
  osConfig,
  ...
}:
# youtube-gate（ユーザー層）— 既定ブラウザ Zen への二重掛けだけ。
#
# なぜシステム全体 PAC（darwin.nix）だけで済ませないか：あちらは PAC 配布デーモンが落ちると
# macOS が DIRECT にフォールバックする＝ fail-open。日常の入口である Zen は独立経路で塞ぐ。
#
# なぜ policies.json ではないか：Zen は macOS の Managed Preferences を読まず
# （zen-browser/desktop#12363）、policies.json は Zen.app 内に置くとコード署名が壊れる。
# user.js なら profile 内で完結する。file:// PAC が使えるのは Firefox 系の仕様（macOS 側は廃止済み）。
#
# 撤去しても prefs.js に pref が焼き付いて残る。だから撤去は darwin.nix の
# `my.youtubeGate.enable = false;` を先に1回 rebuild する：そのときここは user.js に
# network.proxy.type = 0（プロキシを使わない）を書き、prefs.js の値を上書きする。
# Zen を1回起動して prefs.js に反映されてから import を外すこと。
# スイッチは nix-darwin 側にあるので、home-manager からは osConfig で読む。
#
# ## 2026-08-27：プロファイルパスの二重管理をやめた（事故の再発防止）
#
# 旧構成はこのファイルが `home.file."…/Profiles/<ID>/user.js"` を直接置いていた。
# `home.file` はディレクトリごと作ってしまうので、**Zen 側でプロファイルが作り直されて ID が
# 変わると、存在しないプロファイルに user.js を書き続けて黙って無効化される**。実際に踏んだ：
# 稼働プロファイルが `tof5kg3s.Default (release)-1` に移った後もここは `tbq2aiii.…` を
# 指したままで、稼働側の prefs.js には `network.proxy.*` が1行も無く **ゲートが完全に死んでいた**。
#
# 現構成では **プロファイルの場所を知っているのは modules/apps/zen/home.nix ただ1箇所**で、
# このモジュールは `settings`（＝ user.js）に pref を寄せるだけ。パスを持たない＝ずれようがない。
let
  pac = import ./pac.nix {inherit pkgs;};
  enabled = osConfig.my.youtubeGate.enable;
in {
  # user.js は毎起動読まれる＝ UI から変えても再起動で戻る（恒久解除ができない）。
  # 実際の書き出し先は zen モジュールが所有する（上のコメント参照）。
  programs.zen-browser.profiles.default.settings =
    if enabled
    then {
      "network.proxy.type" = 2;
      "network.proxy.autoconfig_url" = "file://${pac}";
    }
    else {
      # 掃除：prefs.js に焼き付いた PAC 設定を「プロキシを使わない」で上書きする。
      "network.proxy.type" = 0;
    };
}
