{ config, lib, ... }:
# Downloads 配下を入口で仕分けるためのディレクトリを常設する。
# 保存先の振り分け本体は modules/system.nix の CustomUserPreferences
# (screencapture / Chrome / Firefox 系ポリシー) が担う。
{
  home.activation.ensureDownloadDirs =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${config.home.homeDirectory}/Downloads/screenshots" \
               "${config.home.homeDirectory}/Downloads/chrome" \
               "${config.home.homeDirectory}/Downloads/firefox" \
               "${config.home.homeDirectory}/Downloads/zen"
    '';
}
