{pkgs, ...}:
###################################################################################
#
#  youtube-gate（システム層）— macOS のシステム全体プロキシ（PAC）で YouTube を遮断し、
#  逃げ道を LibreWolf 1本だけ残す。
#
#  ■ なぜ /etc/hosts（custom/network-block）を使わないか
#    hosts は全プロセスに効くため yt-dlp まで巻き添えで死ぬ。システムプロキシなら
#    CFNetwork / Chromium 系のアプリだけが従い、CLI は素通しになる。**CLI が生きているのが
#    要件**なので hosts には戻さない。
#
#  ■ なぜ file:// の PAC ではなく HTTP サーバを立てているか
#    macOS は Mojave 以降ローカル PAC ファイル（file://）のサポートを廃止した。
#    MIME を application/x-ns-proxy-autoconfig で明示しているのも、CFNetwork が
#    Content-Type にうるさいことがあるため。
#
#  ■ なぜ network-block/darwin.nix に統合しないか
#    あちらの WARNING は「/etc/hosts・DNS リゾルバ状態を触るなら統合しろ」と言っている。
#    こちらが触るのは networksetup のプロキシ設定だけで対象サブシステムが異なるため、
#    別モジュールのままにしてある（postActivation は独立に連結され競合しない）。
#
#  ■ 分かった上で放置している穴
#    - PAC サーバが落ちると macOS は DIRECT にフォールバックする＝ fail-open。
#      KeepAlive で緩和。Zen だけは home.nix が file:// PAC を直接指していて独立に塞がる。
#    - System 設定から手でプロキシを切れる（10 分ごとの enforce が握り直すので恒久化はしない）。
#    - Chromium 系は `--no-proxy-server` 付きで起動すれば誰でも抜けられる。
#      **これは摩擦装置でありセキュリティ境界ではない**。塞ぐなら per-app ファイアウォールの領域。
#    - Chrome もブロック対象。ブラウザエージェントが YouTube を要するようになったら要見直し
#      （Chrome の設定自体には触れていない）。
#
#  ■ 撤去するときに残るもの
#    nix は networksetup で書いた状態を巻き戻さない。module を消すと参照先の PAC サーバだけ
#    死に、System 設定 → ネットワーク → プロキシに死んだ URL が有効チェック付きで居残る。
#    撤去時は全サービスで off にすること：
#      /usr/sbin/networksetup -listallnetworkservices | tail -n +2 | sed 's/^\*//' |
#        while IFS= read -r s; do /usr/sbin/networksetup -setautoproxystate "$s" off; done
#    Zen 側（home.nix）の pref も prefs.js に焼き付く。あちらのヘッダも参照。
#
###################################################################################
let
  pac = import ./pac.nix {inherit pkgs;};
  librewolf = import ./librewolf.nix {inherit pkgs;};

  port = "8073";
  pacUrl = "http://127.0.0.1:${port}/youtube-gate.pac";

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
in {
  # 逃げ道のブラウザ。/Applications/Nix Apps に入って Spotlight / Raycast から開ける。
  environment.systemPackages = [librewolf];

  # PAC 配布サーバ。落ちたら即復帰（fail-open を最小化する）。
  #
  # ⚠ `UserName` を足すな。`nobody` にすると StandardErrorPath（root 所有 644）を開けず
  # **ジョブが spawn 前に沈黙して死ぬ**（2026-08-03 実測：プロセス無し・err ログ 0 バイト・
  # システムログにも記録なし＝気づけない）。ここが落ちると macOS は DIRECT に
  # フォールバックする＝遮断が丸ごと無効化される。どうしても下げるなら
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
}
