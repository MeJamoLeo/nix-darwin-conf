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
  ];
})
