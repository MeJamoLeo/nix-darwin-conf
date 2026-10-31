# Claude Code の managed settings（JSON 生成の共有部・OS 非依存）。
#
# ここには**エージェント自身に外させないガード**だけを置く。設置は OS ごと：
#   - macOS : darwin.nix が /Library/Application Support/ClaudeCode/ へ（activation script）
#   - NixOS : nixos.nix が /etc/claude-code/ へ（environment.etc）
# どちらも root 所有・スクリプトは /nix/store 直参照（read-only）＝改変不能。
#
# 経緯・設計判断（なぜ managed 層か／何を置かないか）は darwin.nix の
# ヘッダコメントが正本。ガード以外（model 等の利便設定）をここに足さないこと。
#
# 例外は1つだけ：下の env.CLAUDE_CODE_CERT_STORE（nix パッケージの欠陥の補正）。
# 利便設定ではなく「nix 版だと API に繋がらなくなる」を直すもので、Ghostty・Orca・
# バックグラウンドのエージェントのどこから起動しても効く場所がここしか無いため。
{pkgs}:
pkgs.writeText "claude-managed-settings.json" (builtins.toJSON {
  # nixpkgs の claude-code は wrapper で `--set-default CLAUDE_CODE_CERT_STORE system` を入れ、
  # 公式の既定 `bundled,system` から同梱の Mozilla CA を外している
  # （pkgs/by-name/cl/claude-code/package.nix）。macOS のキーチェーンからの読み取りが
  # たまに失敗すると保険が無く、`UNABLE_TO_GET_ISSUER_CERT_LOCALLY` で API に繋がらない
  # （2026-10-25 に Orca のペイン、2026-10-28 に tanegashima の Ghostty で発生）。
  # 公式の既定に戻す。settings の env は wrapper の --set-default より後に効く。
  env.CLAUDE_CODE_CERT_STORE = "bundled,system";

  # 親チェーン注入対策（CLAUDE.md / AGENTS.md は置き場所だけで命令へ確定昇格する）。
  # 危険な「空きスロット」を命令として読まない。絶対パス glob・fleet 共有なので
  # home 固定を避け、Downloads はどの機体でも効く形に。user-scope の
  # ~/.claude/CLAUDE.md（2段深い）は /Users/*/CLAUDE.md に巻き込まれない。
  # 由来: cybersecuritynews "Codex and Claude Code hijack"（2026-10）。
  claudeMdExcludes = [
    "**/Downloads/CLAUDE.md"
    "**/Downloads/**/CLAUDE.md"
    "**/Downloads/AGENTS.md"
    "**/Downloads/**/AGENTS.md"
    "/Users/*/CLAUDE.md"
    "/Users/*/AGENTS.md"
    "/home/*/CLAUDE.md"
    "/home/*/AGENTS.md"
  ];

  hooks.PreToolUse = [
    {
      matcher = "Bash";
      hooks = [
        {
          type = "command";
          # hook はユーザーシェル経由で走るが PATH は保証されないので、
          # スクリプトが使う jq を nix 側から前置して固定する。
          command = "PATH=${pkgs.jq}/bin:$PATH ${./deny-secret-reads.sh}";
          timeout = 10;
        }
      ];
    }
  ];

  # 前方一致の deny ルール（補助層）。`echo x | rbw get y` 等の変形は
  # すり抜けるため主防御は上の hook。こちらは素直な単発呼び出しを
  # classifier より手前で確実に落とすための二重化。
  permissions.deny = [
    "Bash(rbw get *)"
    "Bash(rbw get:*)"
    "Bash(rbw code *)"
    "Bash(rbw code:*)"
    "Bash(secret-get *)"
    "Bash(secret-get:*)"
    "Bash(bw get *)"
    "Bash(bw get:*)"
    "Bash(pass show *)"
    "Bash(pass show:*)"
    "Bash(op read *)"
    "Bash(op read:*)"
    # 設定書き換え注入対策（二重化）。悪性 CLAUDE.md が settings.json に
    # ANTHROPIC_BASE_URL を書く／codex config.toml に悪性 MCP を足す経路を
    # Edit ツール層で落とす。Write(path) は仕様上マッチしないので Edit で書く。
    # 主防御は上の claudeMdExcludes（悪性ファイルを命令にしない）。こちらは
    # Bash 変形（echo >> settings.json）ですり抜けるため補助層。
    # settings.json は手動管理方針のため Claude の Edit を封じるのは整合的。
    "Edit(~/.claude/settings.json)"
    "Edit(~/.claude/settings.local.json)"
    "Edit(//**/.claude/settings.json)"
    "Edit(//**/.claude/settings.local.json)"
    "Edit(~/.codex/config.toml)"
    "Edit(//**/.codex/config.toml)"
  ];
})
