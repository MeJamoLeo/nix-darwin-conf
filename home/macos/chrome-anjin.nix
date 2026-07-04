{pkgs, ...}: let
  chromeApp = "/Applications/Google Chrome.app";

  chrome-anjin = pkgs.writeShellScriptBin "chrome-anjin" ''
    set -euo pipefail
    if [ ! -d "${chromeApp}" ]; then
      echo "chrome-anjin: Google Chrome not found at ${chromeApp}" >&2
      exit 1
    fi
    profile="Anjin"
    case "''${1:-}" in
      txst)
        profile="Anjin-txst"
        shift
        ;;
    esac
    exec open -na "Google Chrome" --args --profile-directory="$profile" "$@"
  '';
in {
  home.packages = [chrome-anjin];

  targets.darwin.defaults."com.google.Chrome" = {
    # Claude in Chrome を全プロファイル (anjin 含む) に強制インストール。
    # 注: この domain の書き込みは home-manager (targets.darwin.defaults) に一本化する。
    # nix-darwin 側 CustomUserPreferences と併用すると後勝ちで消し合う。
    ExtensionInstallForcelist = [
      "fcoeoabgfenejglbffodgkkbkcdhcgfn;https://clients2.google.com/service/update2/crx"
    ];
    ExtensionSettings = {
      "fcoeoabgfenejglbffodgkkbkcdhcgfn" = {
        runtime_blocked_hosts = [
          "*://accounts.google.com"
          "*://myaccount.google.com"
          "*://passwords.google.com"
          "*://mail.google.com"
          "*://login.microsoftonline.com"
          "*://appleid.apple.com"
          "*://*.icloud.com"
        ];
      };
    };
  };
}
