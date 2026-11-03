{
  config,
  lib,
  ...
}:
##########################################################################
#
#  pf（パケットフィルタ）：外向きの物理 IF では、外から始まる接続を全部落とす。
#  リモートからの入口は Tailscale（utun）だけにする。
#
#  なぜ要るか（2026-11-01 実測）：ogasawara は
#  - en0（有線）にグローバル IP が直付けで NAT が無い
#  - en1（建物の Wi-Fi）は 100.70.x で、Tailscale と同じ 100.64.0.0/10 を使う
#  テザリング越しの nmap で 22/88/5000/5900/6771/7000/49152/49457 が
#  インターネットから open だった。画面共有などのシステムサービスは
#  ALF を素通りするので、ALF では閉じられない。
#
#  設計：
#  - ポートを列挙して閉じる形にしない。新しく待ち受けるアプリが出るたびに漏れる。
#    IF 単位で「入ってくる新規接続は全部落とす」既定拒否にする。
#  - 送り元アドレスで Tailscale を判定しない。en1 の LAN が同じ 100.64/10 を
#    使っているので、送り元では区別できない。
#  - Tailscale は en0/en1 の上を、こちらから始めた UDP で通るので影響しない
#    （返りは pf の状態表で通る）。利用者は utun 側で受けるので、この規則に当たらない。
#
#  仕組み：
#  - ルールは /etc/pf.conf そのものに書く。macOS は起動時に com.apple.pfctl が
#    /etc/pf.conf を読み込む（有効化はしない）。正規の読み込み経路なので、
#    読み込み順の競合も入れ直しも要らない。
#  - 有効化だけを下の launchd daemon が起動時に1回やる。有効化はルールの
#    読み込みと独立なので、com.apple.pfctl との前後は問わない。
#  - Apple 既定の anchor（com.apple/*）は残す。AirDrop やインターネット共有が
#    動的に差し込む anchor の受け口になっている。
#
#  macOS 更新で /etc/pf.conf の既定が変わっていたら、knownSha256Hashes で
#  switch が止まる。差分を見て下の Apple 部分を追従させる。
#
##########################################################################
let
  cfg = config.my.firewall;
  ifs = lib.concatStringsSep " " cfg.closedInterfaces;
in {
  options.my.firewall.closedInterfaces = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    example = ["en0" "en1"];
    description = "外から始まる接続を全部落とす IF。こちらから始めた通信の返りと、DHCP・IPv6 の近隣探索だけは通す。";
  };

  config = lib.mkIf (cfg.closedInterfaces != []) {
    environment.etc."pf.conf" = {
      # nix-darwin 管理前の macOS 既定 /etc/pf.conf。これ以外の中身なら上書きせず止まる。
      knownSha256Hashes = ["6fb5b260918922ca5ca4dfb296967d8edb9c12f2c043f26b64590758441d682d"];
      text = ''
        # nix-darwin が管理（modules/base/firewall/darwin.nix）。手で編集しない。

        # ── Apple 既定（macOS の /etc/pf.conf と同じ）──
        scrub-anchor "com.apple/*"
        nat-anchor "com.apple/*"
        rdr-anchor "com.apple/*"
        dummynet-anchor "com.apple/*"
        anchor "com.apple/*"
        load anchor "com.apple" from "/etc/pf.anchors/com.apple"

        # ── 外向き IF：外から始まる接続は落とす ──
        closed = "{ ${ifs} }"
        # こちらから始めた通信は状態を作って通す（返りはこの状態で通る）
        pass out quick on $closed all keep state
        # アドレス取得に要る最小限
        pass in quick on $closed inet proto udp from any port 67 to any port 68
        pass in quick on $closed inet6 proto udp from any port 547 to any port 546
        pass in quick on $closed inet6 proto icmp6 icmp6-type { routeradv, neighbrsol, neighbradv, redir }
        block drop in quick on $closed all
      '';
    };

    # pf の有効化（起動時に1回）。-e は有効済みだと非0で返るので終了コードは見ない。
    launchd.daemons.pf-enable.serviceConfig = {
      ProgramArguments = ["/bin/sh" "-c" "/sbin/pfctl -q -e 2>/dev/null; exit 0"];
      RunAtLoad = true;
    };

    # switch 時にも新しいルールを即時反映する（再起動を待たない）。
    system.activationScripts.postActivation.text = lib.mkAfter ''
      /sbin/pfctl -q -f /etc/pf.conf && /sbin/pfctl -q -e 2>/dev/null || true
    '';
  };
}
