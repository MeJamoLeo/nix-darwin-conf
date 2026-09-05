# Claude Code の managed settings（JSON 生成の共有部・OS 非依存）。
#
# ここには**エージェント自身に外させないガード**だけを置く。設置は OS ごと：
#   - macOS : darwin.nix が /Library/Application Support/ClaudeCode/ へ（activation script）
#   - NixOS : nixos.nix が /etc/claude-code/ へ（environment.etc）
# どちらも root 所有・スクリプトは /nix/store 直参照（read-only）＝改変不能。
#
# 経緯・設計判断（なぜ managed 層か／何を置かないか）は darwin.nix の
# ヘッダコメントが正本。ガード以外（model 等の利便設定）をここに足さないこと。
{pkgs}:
pkgs.writeText "claude-managed-settings.json" (builtins.toJSON {
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
    "Bash(bw get *)"
    "Bash(bw get:*)"
    "Bash(pass show *)"
    "Bash(pass show:*)"
    "Bash(op read *)"
    "Bash(op read:*)"
  ];
})
