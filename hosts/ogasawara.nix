# ogasawara — Mac mini M4（母艦）。
# 役割は mac-workstation そのもので、機体固有の差分は Hermes Agent だけ。
{username, ...}: {
  imports = [../profiles/mac-workstation.nix];

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
  ];
}
