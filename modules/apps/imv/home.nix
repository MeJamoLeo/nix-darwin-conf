# imv — x1nano（NixOS）の画像ビューア。Wayland ネイティブで軽く、操作が vim 寄り
# （h/j/k/l で移動、+/- で拡大縮小、n/p で次・前の画像、q で閉じる）。PDF の sioyek と同じ考え方。
# mac は OS 標準のプレビューのままでよいので Linux だけで読む（profiles/nixos-laptop.nix）。
#
# 既定アプリの登録は sioyek と同じく activation の xdg-mime で行う
# （~/.config/mimeapps.list を丸ごと奪わない）。導入前は png が thunar-bulk-rename に
# 吸われていて、jpg 等は未設定だった（2026-10-24）。
{
  lib,
  pkgs,
  ...
}: {
  programs.imv.enable = true;

  home.activation.imvImageDefault = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${pkgs.xdg-utils}/bin/xdg-mime default imv.desktop \
      image/png image/jpeg image/gif image/webp image/bmp image/tiff image/heif image/avif image/svg+xml
  '';
}
