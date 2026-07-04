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
