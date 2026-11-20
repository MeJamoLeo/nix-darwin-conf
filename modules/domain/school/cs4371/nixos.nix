# CS4371（セキュリティ）の実験環境。VirtualBox で攻撃/標的 VM を回し、Wireshark で観測する。
# 学期が終わったら modules/_archive/ へ（domain/school の他の科目と同じ扱い）。
{username, ...}: {
  virtualisation.virtualbox.host.enable = true;
  # Do not restart vboxnet0 on switch: stopping it fails the dependent unit and `nh os switch`
  # aborts with status 4. It is recreated on reboot.
  systemd.services.vboxnet0.restartIfChanged = false;
  systemd.services.network-addresses-vboxnet0.restartIfChanged = false;

  programs.wireshark.enable = true;
  users.users.${username}.extraGroups = ["vboxusers" "wireshark"];
}
