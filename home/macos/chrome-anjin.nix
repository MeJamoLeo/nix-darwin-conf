{pkgs, lib, ...}: let
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

  # Claude in Chrome 拡張の宣言的インストール — External Extensions 方式 (実機検証済み 2026-07-04)。
  # 経緯: ExtensionInstallForcelist はユーザー defaults 経由だと "recommended" レベル扱いで
  # 無視される (mandatory 必須 = /Library/Managed Preferences か MDM が要る)。External Extensions は
  # ユーザー空間で機能する公式経路。制約: プロファイル毎に初回1回だけ有効化の確認バブルが出る。
  home.activation.chromeExternalExtensions =
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      extdir="$HOME/Library/Application Support/Google/Chrome/External Extensions"
      mkdir -p "$extdir"
      printf '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }\n' \
        > "$extdir/fcoeoabgfenejglbffodgkkbkcdhcgfn.json"
    '';

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
