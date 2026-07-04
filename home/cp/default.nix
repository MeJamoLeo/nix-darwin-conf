{ ... }:
{
  # cp = competitive-programming の家族モジュール。
  #   tools.nix     — cp-go / cp-go-launch（問題を開く CLI）
  #   dashboard.nix — CP ダッシュボード（壁紙/ライブ層/スクリーンセーバー常駐）
  imports = [
    ./tools.nix
    ./dashboard.nix
  ];
}
