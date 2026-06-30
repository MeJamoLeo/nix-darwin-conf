{ pkgs, ... }:
{
  # Competitive-programming practice tools, ported from x1nano:~/nixos-cp/tools.
  # Script bodies live in ./scripts/ (writeShellScriptBin adds the bash shebang).
  #
  #   cp-go         clipboard AtCoder URL -> ~/cp/contests/.../ + oj download + nvim
  #   cp-go-launch  alt-g entry: drop/focus a cp-go window in cmux's tmux (no spawn)
  #
  # alt-g binding lives in home/macos/aerospace.nix and calls cp-go-launch via
  # the user profile bin (config.home.profileDirectory).
  home.packages = [
    (pkgs.writeShellScriptBin "cp-go" (builtins.readFile ./scripts/cp-go))
    (pkgs.writeShellScriptBin "cp-go-launch" (builtins.readFile ./scripts/cp-go-launch))
  ];
}
