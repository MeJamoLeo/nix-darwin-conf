# tanegashima — MacBook Air M1（持ち出し機）。
# 役割は mac-workstation そのもので、機体固有の差分は todo のリモートラッパーだけ。
{username, ...}: {
  imports = [../profiles/mac-workstation.nix];

  # todo-board の本体（home.nix）は ogasawara 専用（データの正本 ~/Store が母艦にあるため）。
  # tanegashima には `todo` を「母艦へ SSH して実行する薄いラッパー」として入れる。
  home-manager.users.${username}.imports = [
    ../modules/custom/todo-board/remote.nix
  ];
}
