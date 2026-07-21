{
  lib,
  pkgs,
  ...
}: let
  # Self-authored Claude Code skills live in ./skills/<name>/.
  # Drop a new skill directory there and it is symlinked into
  # ~/.claude/skills/<name> automatically — no need to list it here.
  #
  # Scope is deliberately per-skill (not the whole ~/.claude/skills dir):
  # the skills directory also holds runtime-written skills (continuous-learning)
  # and ECC-installed ones, which must NOT be clobbered by Home Manager.
  skillsDir = ./skills;
  skillNames =
    builtins.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir));
in {
  # Claude Code CLI 本体は nixpkgs で管理（Homebrew cask から移行 2026-07-08）。
  # 理由: /nix/store 配下は quarantine が付かず Gatekeeper の「DLされたアプリ」
  # 確認が原理的に出ない（SSH 先の headless 機で詰まらない）＋ store は
  # read-only なので内蔵アップデータも無効化され flake.lock でバージョン固定。
  # 更新は `nix flake update nixpkgs-darwin` → rebuild で意図的に行う。
  # GUI の Claude デスクトップ版は nixpkgs 非収録のため cask のまま (modules/homebrew-base/darwin.nix)。
  home.packages = [pkgs.claude-code];

  home.file =
    {
      # グローバル CLAUDE.md（全プロジェクト横断ルール＋vault マウントポイント）。
      # 正史はこの repo の ./CLAUDE.md（編集→rebuild で反映）。settings.json と違い
      # runtime に書き換えられないファイルなので store symlink で所有してよい
      # （settings.json を所有しない決定は modules/apps/herdr/home.nix 参照）。
      ".claude/CLAUDE.md" = {
        source = ./CLAUDE.md;
        force = true; # 手動運用時代の ~/.claude/CLAUDE.md が残っていても上書きする
      };

      # SessionStart hook: auto-memory 代替＝vault hot.md の全プロジェクト注入。
      # settings.json 側の登録は存在ガード付き1行（herdr-auto-name と同パターン。
      # settings.json 自体を所有しない理由は modules/apps/herdr/home.nix 参照）。
      ".claude/hooks/vault-context-inject.sh" = {
        source = ./vault-context-inject.sh;
        executable = true;
        force = true; # rebuild 前に手動配置した同名ファイルを上書きしてよい
      };
    }
    // builtins.listToAttrs (map (name: {
      name = ".claude/skills/${name}";
      value.source = skillsDir + "/${name}";
    })
    skillNames);
}
