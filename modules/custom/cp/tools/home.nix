{
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # スクリプトは mac 前提の pbpaste / pbcopy / open で書いてある。Linux（x1nano）では
  # 同名の小さな代役（wl-paste / wl-copy / xdg-open）を PATH の先頭に差して、本体は1本のまま
  # 両 OS で動かす（2026-10-23。グローバルには置かない＝他のコマンドの open を奪わない）。
  macShims = pkgs.symlinkJoin {
    name = "cp-mac-shims";
    paths = [
      (pkgs.writeShellScriptBin "pbpaste" ''exec ${pkgs.wl-clipboard}/bin/wl-paste --no-newline "$@"'')
      (pkgs.writeShellScriptBin "pbcopy" ''exec ${pkgs.wl-clipboard}/bin/wl-copy "$@"'')
      (pkgs.writeShellScriptBin "open" ''exec ${pkgs.xdg-utils}/bin/xdg-open "$@"'')
    ];
  };
  script = name:
    pkgs.writeShellScriptBin name (
      lib.optionalString (!isDarwin) ''
        PATH=${macShims}/bin:$PATH
      ''
      + builtins.readFile (./scripts + "/${name}")
    );

  # oj wrapper — pass through to the real oj; on a successful `oj test` in a
  # problem dir (has .problem_url), drop a marker so the dashboard STOPWATCH
  # arms its fast watch (#36: local test pass predicts an imminent submission).
  oj = pkgs.writeShellScriptBin "oj" ''
    rc=0
    ${pkgs.online-judge-tools}/bin/oj "$@" || rc=$?
    case "''${1:-}" in
      t|test)
        if [ "$rc" -eq 0 ] && [ -f .problem_url ]; then
          url=$(cat .problem_url)
          pid=''${url##*/tasks/}
          mkdir -p "$HOME/.cache/cp-dashboard"
          ${pkgs.jq}/bin/jq -n --arg t "$pid" --argjson p "$(date +%s)" \
            '{task_id: $t, passed_at: $p}' \
            > "$HOME/.cache/cp-dashboard/test-passed.json"
          if [ -f "$HOME/cp-dashboard/upstream/stopwatch_poll.py" ]; then
            (${pkgs.python3}/bin/python3 "$HOME/cp-dashboard/upstream/stopwatch_poll.py" >/dev/null 2>&1 &)
          fi
        fi;;
    esac
    exit "$rc"
  '';
in {
  # Competitive-programming practice tools, ported from x1nano:~/nixos-cp/tools.
  # Script bodies live in ./scripts/ (writeShellScriptBin adds the bash shebang).
  #
  #   oj            wrapped online-judge-tools (test-pass marker, see above)
  #   cp-go         clipboard AtCoder URL -> ~/cp/contests/.../ + oj download + nvim
  #   cp-go-launch  alt-g entry: drop/focus a cp-go window in cmux's tmux (no spawn)
  #   cp-test       oj test with language auto-detect (.py -> python3, .cpp -> g++)
  #   cp-submit     contest: curl auto-submit / practice: clipboard + browser;
  #                 arms the STOPWATCH fast watch on invocation
  #   cp-login      paste REVEL_SESSION -> Bitwarden; Keychain cache for stopwatch
  #
  # ⚠ alt-g は 2026-09-09 時点で **どこにもバインドされていない**。かつては
  # modules/apps/aerospace/home.nix が profile bin 経由で cp-go-launch を叩いていたが、
  # AeroSpace の退役（modules/_archive/aerospace）で消えた。後継の OmniWM は
  # 「固定コマンド ID → binding」表で **任意コマンドを実行する hotkey ID を持たない**
  # （169 ID を全走査して0件）ため、同じことを OmniWM 単体では表現できない。
  # 復活させるなら skhd 等の外部ホットキーデーモンか、
  # `omniwmctl watch --exec` へ逃がす。cp-go-launch 自体は生きているので CLI では叩ける。
  # mac だけのもの：cp-go-launch は Ghostty を `open -a` で起こす、cp-login は Keychain に
  # キャッシュを書く（どちらも macOS の仕組みそのもの）。Linux 版は未移植。
  home.packages =
    [oj (script "cp-go")]
    ++ lib.optional isDarwin (script "cp-go-launch")
    ++ [(script "cp-test") (script "cp-submit")]
    ++ lib.optional isDarwin (script "cp-login");
}
