{ pkgs, ... }:
let
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
in
{
  # Competitive-programming practice tools, ported from x1nano:~/nixos-cp/tools.
  # Script bodies live in ./scripts/ (writeShellScriptBin adds the bash shebang).
  #
  #   oj            wrapped online-judge-tools (test-pass marker, see above)
  #   cp-go         clipboard AtCoder URL -> ~/cp/contests/.../ + oj download + nvim
  #   cp-go-launch  alt-g entry: drop/focus a cp-go window in cmux's tmux (no spawn)
  #   cp-login      paste REVEL_SESSION -> Keychain (stopwatch freeze detection)
  #
  # alt-g binding lives in home/macos/aerospace.nix and calls cp-go-launch via
  # the user profile bin (config.home.profileDirectory).
  home.packages = [
    oj
    (pkgs.writeShellScriptBin "cp-go" (builtins.readFile ./scripts/cp-go))
    (pkgs.writeShellScriptBin "cp-go-launch" (builtins.readFile ./scripts/cp-go-launch))
    (pkgs.writeShellScriptBin "cp-login" (builtins.readFile ./scripts/cp-login))
  ];
}
