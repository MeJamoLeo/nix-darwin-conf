# dejima — 使い捨て VM (tart sandbox)。mac-workstation からの引き算で成立する島。
{lib, ...}: {
  imports = [../profiles/mac-workstation.nix];

  # App Store 経由アプリは Apple ID ログインが必要で、headless な使い捨て
  # VM では毎回サインインするのが面倒なため空にする（casks/brews は入る）。
  homebrew.masApps = lib.mkForce {};

  # dejima は headless の使い捨て島。Homebrew の GUI アプリ(~30個)は
  #  (1) 50GB の VM ディスクに収まらず (2) headless では起動して使えない
  # ので、dejima 限定で Homebrew activation ごと無効化する。
  # → switch が緑・数十秒、base が軽い。casks/brews の宣言は実機用に
  #   config に残るが dejima では実行しない（ogasawara/tanegashima は無変更）。
  homebrew.enable = lib.mkForce false;

  # tart の NAT は MTU ブラックホール（小パケットは通るが TLS の大パケットが
  # 落ちる）。en0 の MTU を 1400 に下げると外向き TLS が通る。
  # postActivation は boot 時に走らない/早すぎるので、専用 LaunchDaemon で
  # 「起動ごと・en0 が上がるまでリトライ」で確実に下げる（switch 時も
  # RunAtLoad で再発火）。→ respin 後も自動で効く自己修復。
  launchd.daemons.dejima-mtu = {
    script = ''
      for _ in $(seq 1 15); do
        /sbin/ifconfig en0 mtu 1400 && exit 0
        sleep 2
      done
    '';
    serviceConfig = {
      RunAtLoad = true;
      StandardErrorPath = "/var/log/dejima-mtu.log";
    };
  };
}
