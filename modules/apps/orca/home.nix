# Orca (AppImage) in the launcher. The AppImage itself lives outside the store at
# ~/Applications/Orca.AppImage: Orca ships no stable download URL to pin.
{
  config,
  lib,
  pkgs,
  ...
}: let
  appImage = "${config.home.homeDirectory}/Applications/Orca.AppImage";
in {
  xdg.desktopEntries.orca = {
    name = "Orca";
    comment = "IDE for parallel agentic development";
    # appimage-run, not the AppImage directly: NixOS has no FHS loader for it.
    exec = "${pkgs.appimage-run}/bin/appimage-run ${appImage} %U";
    icon = "orca-ide";
    terminal = false;
    categories = ["Development"];
    mimeType = ["x-scheme-handler/orca"];
    settings.StartupWMClass = "orca";
  };

  # Re-extract the icons on every switch so they follow AppImage updates. unsquashfs at the
  # runtime's end offset, not --appimage-extract: that would execute the downloaded file.
  home.activation.orcaIcon = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f "${appImage}" ]; then
      tmp=$(mktemp -d)
      off=$(${pkgs.python3}/bin/python3 ${./elf-end.py} "${appImage}")
      if ${pkgs.squashfsTools}/bin/unsquashfs -q -n -o "$off" -d "$tmp/root" "${appImage}" usr/share/icons >/dev/null 2>&1; then
        mkdir -p "${config.xdg.dataHome}/icons"
        cp -rL --no-preserve=mode "$tmp/root/usr/share/icons/." "${config.xdg.dataHome}/icons/"
      fi
      rm -rf "$tmp"
    fi
  '';
}
