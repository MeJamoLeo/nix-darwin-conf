{
  config,
  lib,
  pkgs,
  hunk,
  nixpkgs-claude,
  ...
}: let
  hunkPkg = hunk.packages.${pkgs.stdenv.hostPlatform.system}.hunk;

  # claude-code 専用 nixpkgs（flake.nix の nixpkgs-claude input）。
  # ★ legacyPackages ではなく import する理由：claude-code は
  #   meta.license = unfree なので、こちらの nixpkgs.config.allowUnfree
  #   （modules/base/nix-core/darwin.nix）が届かない別 input では eval が拒否される。
  #   firefox-addons で overlay を選んだのと同じ落とし穴（flake.nix 参照）だが、
  #   素の nixpkgs input には overlay が無いので config 付き import で解く。
  pkgsClaude = import nixpkgs-claude {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

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
  # read-only なので内蔵アップデータ（`claude update`）は無効。
  #
  # 版の供給元は専用 input の nixpkgs-claude（2026-10-02 に nixpkgs-darwin から分離）。
  # ★ store が read-only で自己更新できない構成では、**更新経路を作らないかぎり
  #   バージョンは永久に止まる**。実測：pkgs.claude-code は 2.1.220 のまま
  #   上流 2.1.287 まで67版ぶん取り残されていた（`nix flake update` を打つ理由が
  #   日常に無いので誰も打たない）。だから更新を「意図的な操作」にせず、
  #   rebuild の alias `nhds` に埋め込んだ（下）。
  # GUI の Claude デスクトップ版は nixpkgs 非収録のため cask のまま (modules/homebrew-base/darwin.nix)。
  home.packages = [pkgsClaude.claude-code];

  # claude-code の更新は `nhds`（= nh darwin switch -U nixpkgs-claude）で行う。
  # nh 4.x の --update-input が nixpkgs-claude だけを bump する。以前は nh を自作ラッパで
  # 差し替えて自動 commit までしていたが、version 引き継ぎ・git ピン・失敗メッセージの
  # 誤誘導など壊れやすさが見合わないので廃止（2026-10-20）。flake.lock は手で commit する。
  # 素の `nh darwin switch` は bump しない（壊れた疑いのときの逃げ道にもなる）。
  home.shellAliases.nhds = "nh darwin switch -U nixpkgs-claude";

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

      # PreToolUse(Bash) hook: 秘密の平文を stdout に出すコマンドを機械的に拒否。
      # 2026-09-04 に `rbw get --full` の1行目（TXST campus password）がモデルの
      # コンテキストと transcript に載った事故の再発防止。CLAUDE.md の散文では
      # 止まらない種類の事故（判断ではなくうっかりで起きる）なので検知を自動経路に置く。
      # settings.json 側の登録は手動（settings.json を所有しない決定は
      # modules/apps/herdr/home.nix 参照）。
      ".claude/hooks/deny-secret-reads.sh" = {
        source = ./deny-secret-reads.sh;
        executable = true;
        force = true; # rebuild 前に手動配置した同名ファイルを上書きしてよい
      };

      # hunk 同梱の review skill（`hunk skill path` の中身）。自作 skill と違い
      # パッケージから直接 link し、バイナリと skill のバージョンを常に一致させる
      ".claude/skills/hunk-review".source = "${hunkPkg}/skills/hunk-review";
    }
    // builtins.listToAttrs (map (name: {
        name = ".claude/skills/${name}";
        value.source = skillsDir + "/${name}";
      })
      skillNames);
}
