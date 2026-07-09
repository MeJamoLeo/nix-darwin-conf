{
  lib,
  pkgs,
  ...
}: let
  # Self-authored Claude Code skills live in ./claude/skills/<name>/.
  # Drop a new skill directory there and it is symlinked into
  # ~/.claude/skills/<name> automatically — no need to list it here.
  #
  # Scope is deliberately per-skill (not the whole ~/.claude/skills dir):
  # the skills directory also holds runtime-written skills (continuous-learning)
  # and ECC-installed ones, which must NOT be clobbered by Home Manager.
  skillsDir = ./claude/skills;
  skillNames =
    builtins.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir));
in {
  # Claude Code CLI 本体は nixpkgs で管理（Homebrew cask から移行 2026-07-08）。
  # 理由: /nix/store 配下は quarantine が付かず Gatekeeper の「DLされたアプリ」
  # 確認が原理的に出ない（SSH 先の headless 機で詰まらない）＋ store は
  # read-only なので内蔵アップデータも無効化され flake.lock でバージョン固定。
  # 更新は `nix flake update nixpkgs-darwin` → rebuild で意図的に行う。
  # GUI の Claude デスクトップ版は nixpkgs 非収録のため cask のまま (modules/apps.nix)。
  home.packages = [pkgs.claude-code];

  home.file =
    builtins.listToAttrs (map (name: {
        name = ".claude/skills/${name}";
        value.source = skillsDir + "/${name}";
      })
      skillNames);
}
