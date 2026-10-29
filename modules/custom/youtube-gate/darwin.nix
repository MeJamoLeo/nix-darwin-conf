{
  config,
  lib,
  pkgs,
  ...
}:
###################################################################################
#
#  youtube-gate（システム層）— YouTube を柵の重ね掛けで塞ぐ。
#
#  ■ 柵の一覧（2026-10-28 時点。1枚外しても他が残るように重ねている）
#    1. システム全体の PAC（このファイル）：CFNetwork / Chromium 系のアプリが従う。
#    2. Zen の PAC（home.nix）：Zen が PAC ファイルを直接読む。配布サーバが落ちても効く。
#    3. LibreWolf の PAC（librewolf.nix）：同上。lockPref なので about:config でも外せない。
#    4. /etc/hosts（custom/network-block に `my.networkBlock.extraDomains` で渡す）：
#       プロキシ設定に従わないアプリも含めて Mac 全体で名前を引けなくする。
#    PAC はワイルドカードで動画の配信元（*.googlevideo.com）まで塞げ、DoH にも迂回されない。
#    hosts は PAC を無視するアプリにも効く。互いの穴を塞ぐので両方置いている。
#
#  ■ 2026-10-28：yt-dlp のために hosts を避けていた縛りを外した
#    旧構成は「CLI は素通し」が要件で hosts を使っていなかったが、yt-dlp はどの機体にも
#    入っておらず、要件ごと不要になった。LibreWolf も「唯一の逃げ道」をやめ、
#    履歴を残さない使い捨てブラウザとして残している（librewolf.nix）。
#
#  ■ なぜ file:// の PAC ではなく HTTP サーバを立てているか
#    macOS は Mojave 以降ローカル PAC ファイル（file://）のサポートを廃止した。
#    MIME を application/x-ns-proxy-autoconfig で明示しているのも、CFNetwork が
#    Content-Type にうるさいことがあるため。
#
#  ■ 分かった上で放置している穴
#    - PAC サーバが落ちると macOS は DIRECT にフォールバックする＝ fail-open。
#      KeepAlive で緩和。Zen と LibreWolf は file:// PAC を直接読むので独立に塞がる。
#    - System 設定から手でプロキシを切れる（10 分ごとの enforce が握り直すので恒久化はしない）。
#    - Chromium 系は `--no-proxy-server` 付きで起動すれば PAC を抜けられる（hosts は残る）。
#    - hosts はワイルドカード不可。動画の配信元（rr*---sn-*.googlevideo.com）は名前がランダムで
#      書き切れないので、hosts はページと API だけを止める。
#    - ブラウザの DoH（DNS over HTTPS）は hosts を迂回しうる。一律には止めておらず、
#      抜けたブラウザにだけ止める設定を入れる方針（2026-10-28 時点で未検証）。
#    **これは摩擦装置でありセキュリティ境界ではない**。
#
#  ■ 撤去するとき：いきなりモジュールを消さない
#    nix は networksetup や Zen の prefs.js に書いた状態を巻き戻さない。消す前に
#    `my.youtubeGate.enable = false;` で1回 rebuild すると、下の掃除が走る：
#      - 全ネットワークサービスの PAC を off にする
#      - Zen の user.js に network.proxy.type = 0 を書いて prefs.js の値を上書きする（home.nix）
#      - hosts のドメインと LibreWolf の PAC は nix の所有物なので、自動で消える
#    掃除が済んでから import を外す。2段階なのは、撤去の手間そのものを柵にするため。
#
###################################################################################
let
  cfg = config.my.youtubeGate;
  pac = import ./pac.nix {inherit pkgs;};
  librewolf = import ./librewolf.nix {
    inherit pkgs pac;
    gate = cfg.enable;
  };

  port = "8073";
  pacUrl = "http://127.0.0.1:${port}/youtube-gate.pac";

  # hosts で止める名前（完全一致）。PAC のワイルドカードの代わりに、ページ・API・画像の
  # 代表的なホストを列挙する。Google 系の共用ホスト（*.google.com 等）は入れないこと。
  hostsDomains = [
    "youtube.com"
    "www.youtube.com"
    "m.youtube.com"
    "music.youtube.com"
    "tv.youtube.com"
    "studio.youtube.com"
    "youtu.be"
    "www.youtu.be"
    "youtube-nocookie.com"
    "www.youtube-nocookie.com"
    "youtubei.googleapis.com"
    "youtube.googleapis.com"
    "i.ytimg.com"
    "s.ytimg.com"
    "yt3.ggpht.com"
    "redirector.googlevideo.com"
  ];

  # PAC を配る極小 HTTP サーバ。内容は起動時にメモリへ読み込む（nix store は不変）。
  pacServer = pkgs.writeText "youtube-gate-pac-server.py" ''
    import http.server
    import socketserver

    PAC = open("${pac}", "rb").read()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ns-proxy-autoconfig")
            self.send_header("Content-Length", str(len(PAC)))
            self.end_headers()
            self.wfile.write(PAC)

        def log_message(self, *args):
            pass

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", ${port}), Handler) as httpd:
        httpd.serve_forever()
  '';

  # 全ネットワークサービス（Wi-Fi / Ethernet / VPN …）に PAC を貼り直す。
  # 後から増えたサービスも 10 分以内に握られる。
  applyProxy = pkgs.writeShellScript "youtube-gate-apply" ''
    set -uo pipefail
    ns=/usr/sbin/networksetup

    # 1行目はヘッダ行なので落とす。無効なサービスの先頭 * も剥がす。
    "$ns" -listallnetworkservices 2>/dev/null | tail -n +2 | sed 's/^\*//' |
      while IFS= read -r svc; do
        [ -z "$svc" ] && continue
        "$ns" -setautoproxyurl "$svc" "${pacUrl}" >/dev/null 2>&1 || true
        "$ns" -setautoproxystate "$svc" on >/dev/null 2>&1 || true
      done
  '';

  # enable = false のときの掃除。うちが貼った PAC（URL が一致するもの）だけを off にする。
  # 他のツールが入れたプロキシ設定は触らない。
  removeProxy = pkgs.writeShellScript "youtube-gate-remove" ''
    set -uo pipefail
    ns=/usr/sbin/networksetup

    "$ns" -listallnetworkservices 2>/dev/null | tail -n +2 | sed 's/^\*//' |
      while IFS= read -r svc; do
        [ -z "$svc" ] && continue
        if "$ns" -getautoproxyurl "$svc" 2>/dev/null | grep -qF "${pacUrl}"; then
          # URL は残しても off なら使われない（空にする正規の手段が networksetup に無い）。
          "$ns" -setautoproxystate "$svc" off >/dev/null 2>&1 || true
        fi
      done
  '';
in {
  options.my.youtubeGate.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      YouTube の柵を張るか。false にして1回 rebuild すると、nix が巻き戻さない状態
      （システムの PAC、Zen の prefs.js）を掃除する。撤去はその後で import を外す。
    '';
  };

  config = lib.mkMerge [
    {
      # 履歴を残さない使い捨てブラウザ。柵の有無に関係なく置く（PAC の lock は gate 次第）。
      # /Applications/Nix Apps に入って Spotlight / Raycast から開ける。
      environment.systemPackages = [librewolf];
    }

    (lib.mkIf cfg.enable {
      my.networkBlock.extraDomains = hostsDomains;

      # PAC 配布サーバ。落ちたら即復帰（fail-open を最小化する）。
      #
      # ⚠ `UserName` を足すな。`nobody` にすると StandardErrorPath（root 所有 644）を開けず
      # **ジョブが spawn 前に沈黙して死ぬ**（2026-08-03 実測：プロセス無し・err ログ 0 バイト・
      # システムログにも記録なし＝気づけない）。ここが落ちると macOS は DIRECT に
      # フォールバックする＝システム PAC の柵が丸ごと無効化される。どうしても下げるなら
      # StandardErrorPath を外して unified log に流す形とセットで。
      launchd.daemons.youtube-gate-pac = {
        serviceConfig = {
          ProgramArguments = ["${pkgs.python3}/bin/python3" "${pacServer}"];
          RunAtLoad = true;
          KeepAlive = true;
          StandardErrorPath = "/var/log/youtube-gate-pac.err.log";
        };
      };

      # プロキシ設定の握り直し。手で切られても・サービスが増えても 10 分で戻る。
      # こちらは networksetup が特権を要求するので root のまま。
      launchd.daemons.youtube-gate-enforce = {
        serviceConfig = {
          ProgramArguments = ["${applyProxy}"];
          RunAtLoad = true;
          StartInterval = 600;
          StandardErrorPath = "/var/log/youtube-gate-enforce.err.log";
        };
      };

      # rebuild 直後にデーモンの次回起動を待たず即座に効かせる。
      system.activationScripts.postActivation.text = ''
        echo "applying youtube-gate proxy (system-wide PAC)..." >&2
        ${applyProxy} || true
      '';
    })

    (lib.mkIf (!cfg.enable) {
      # デーモンは宣言から消えるので nix-darwin が unload する。残るのは networksetup の状態だけ。
      system.activationScripts.postActivation.text = ''
        echo "removing youtube-gate proxy (system-wide PAC)..." >&2
        ${removeProxy} || true
      '';
    })
  ];
}
