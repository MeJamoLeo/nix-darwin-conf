{ config, pkgs, lib, ... }:
{
  # desktop-switcher — デスクトップ壁紙レイヤーを alt+N で切替する tiny dispatcher。
  # 実装は ./bin/desktop-switch（bash 1本）。仕組みは script 冒頭コメントを参照。
  # aerospace 側の binding は modules/apps/aerospace/home.nix、signal handler は
  # 各 dashboard（calendar-dashboard / cp/dashboard）の swift 側に同居する。
  #
  # なぜ custom バケツか（modules/CLAUDE.md 判定）:
  #   価値の中心が自分のコード（signal 配線・状態管理・reload シーケンス）で、
  #   既製品の設定ではない。cp/dashboard と calendar-dashboard を跨ぐ「切替」
  #   という単独の関心事なのでどちらの下でもなく独立モジュールが妥当。

  home.file."bin/desktop-switch" = {
    source = ./bin/desktop-switch;
    executable = true;
  };
}
