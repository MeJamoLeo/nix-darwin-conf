# ogasawara — Mac mini M4（母艦）。
# 役割は mac-workstation そのもので、機体固有の差分は Hermes Agent だけ。
{username, ...}: {
  imports = [../profiles/mac-workstation.nix];

  # tailnet 向けの素の sshd（ポート 2222）。2026-10-24 に追加。
  # ★ この機体は `tailscale up --ssh` で Tailscale SSH が有効なので、tailnet 越しの 22 番は
  #   tailscaled が受ける。その Tailscale SSH は**リモートコマンドの終了コードを返さない**
  #   （x1nano から `ssh ogasawara 'exit 5'` が 0 になる。`ssh -v` で remote software = Tailscale）。
  #   herdr --remote は powershell.exe の失敗（非 0）で「Windows ではない」と判定するため、
  #   ここで迷って `remote command exited before producing its output marker` で落ちていた。
  #   Tailscale SSH は iPhone の鍵なし接続に使っているので止めず、機体どうしは 2222 の
  #   macOS 標準 sshd（鍵だけ・200-remote-access.conf の硬化が効く）に入る。
  #   クライアント側の向け先は modules/base/remote-access/home.nix。
  # 待受は tailnet の IP だけ（en0 はグローバル IP 直付けなので全 IF にすると外に出る）。
  # 起動直後で tailnet が未接続だと bind に失敗するが、KeepAlive が上がるまで再試行する。
  launchd.daemons.sshd-tailnet.serviceConfig = {
    Label = "com.treo.sshd-tailnet";
    ProgramArguments = ["/usr/sbin/sshd" "-D" "-e" "-o" "ListenAddress=100.66.90.8:2222"];
    RunAtLoad = true;
    KeepAlive = true;
    ThrottleInterval = 30;
    StandardErrorPath = "/var/log/sshd-tailnet.log";
  };

  # Hermes Agent はこの機体限定。**profile（＝全機共有）に入れない**理由：
  #   - hermes-agent#default は公開バイナリキャッシュが無く、実測で 1191 derivation の
  #     ローカルビルド＋1.5GiB DL / 6.3GiB 展開（uv2nix が Python ホイールを大量に
  #     ソースビルドする）。tanegashima（M1 Air）と dejima（使い捨て VM）に同じ負荷を
  #     掛ける意味が無い。
  #   - Hermes は cron / gateway で常駐して初めて価値が出るので、常時起動の母艦に
  #     1台だけ置くのが用途とも噛み合う。
  # 他機に広げたくなったら、このブロックを profiles/mac-workstation.nix へ移す。
  home-manager.users.${username}.imports = [
    ../modules/apps/hermes/home.nix
    ../modules/custom/todo-board/home.nix
    ../modules/custom/mail-check/home.nix
    # ../modules/custom/job-watch/home.nix # 一時停止(2026-10-18): job-watch/ が未追跡で評価が落ちるため。仕上げたら戻す
  ];
}
