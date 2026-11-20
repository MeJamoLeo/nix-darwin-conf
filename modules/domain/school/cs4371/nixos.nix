# CS4371（セキュリティ）の実験環境。VirtualBox で攻撃/標的 VM を回し、Wireshark で観測する。
# 学期が終わったら modules/_archive/ へ（domain/school の他の科目と同じ扱い）。
#
# 2026-11-20：VirtualBox の .ko.cer が無くてビルドが落ちる件の一時回避（空の .cer を置く
# stub、2026-10-23〜）を外した。nixpkgs 側の virtualbox-modules 7.2.22 が .cer を出すように
# なり、stub と同じパスで衝突してビルドが落ちるようになったため（上流 issue #575192 の修正）。
{username, ...}: {
  virtualisation.virtualbox.host.enable = true;
  # 設定を切り替えるたびに vboxnet0（ホストオンリーの仮想ネットワーク）を止めて作り直すと、
  # 止まった瞬間に「Address configuration of vboxnet0」が依存失敗し、nh os switch の試し当てが
  # status 4 で落ちて世代が登録されなかった（2026-11-20）。切り替えでは触らず、再起動で
  # 作り直すだけにする。
  systemd.services.vboxnet0.restartIfChanged = false;
  systemd.services.network-addresses-vboxnet0.restartIfChanged = false;

  programs.wireshark.enable = true;
  users.users.${username}.extraGroups = ["vboxusers" "wireshark"];
}
