{pkgs, ...}: let
  ##########################################################################
  #
  #  claude (システム層) — Claude Code の managed settings（macOS 側）。
  #
  #  ~/.claude/settings.json（user 層・home.nix 側の決定で HM は所有しない）とは
  #  別物で、こちらは**エージェント自身に外させないためのガード**だけを置く。
  #  JSON の中身は managed-settings.nix（単一源・NixOS 側 nixos.nix と共有）。
  #
  #  ## なぜ managed 層か（2026-09-05 決定）
  #
  #  2026-09-04、Claude が `rbw get --full | cut -d: -f1` で TXST campus password
  #  を自分のコンテキストと transcript に載せる事故を起こした。対策の
  #  PreToolUse hook を user 層（~/.claude/settings.json）に置くと：
  #    (a) settings.json は HM 非所有の可変ファイルなので他機に伝播しない
  #    (b) エージェント自身が Edit で登録を外せる（ガードが自己解除できる）
  #  managed-settings.json は全設定階層の最上位（user/project/local/--settings の
  #  どれでも上書き不可）かつ root:wheel 0644 なので、両方の穴が閉じる。
  #  スクリプト本体も /nix/store 直参照（read-only）で改変不能。
  #
  #  ## 何を置かないか
  #
  #  - allowManagedHooksOnly: 置かない。true にすると user/project の hook が
  #    全滅する（herdr / vault-context-inject / claude-obsidian の全 hook が死ぬ）。
  #  - allowManagedPermissionRulesOnly: 置かない。user/project の allow 運用を殺す。
  #  - 利便設定（model 等）: managed に置くと /model 等で変えられなくなる。
  #    ガード以外はここに足さないこと。
  #
  ##########################################################################
  managedSettings = import ./managed-settings.nix {inherit pkgs;};
in {
  # nix-darwin に /Library/Application Support 配下を宣言するオプションは無いので
  # activation script（root で走る）で配置する。symlink ではなく cp なのは、
  # ~ 以下と違って /Library に store への symlink を置くと GC/世代切替との
  # 相互作用を考える必要が増えるため（コピーなら generation に依存しない）。
  system.activationScripts.postActivation.text = ''
    echo "installing Claude Code managed settings..." >&2
    /bin/mkdir -p "/Library/Application Support/ClaudeCode"
    /bin/cp -f ${managedSettings} "/Library/Application Support/ClaudeCode/managed-settings.json"
    /usr/sbin/chown root:wheel "/Library/Application Support/ClaudeCode/managed-settings.json"
    /bin/chmod 644 "/Library/Application Support/ClaudeCode/managed-settings.json"
  '';
}
