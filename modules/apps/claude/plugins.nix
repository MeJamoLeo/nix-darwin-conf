{pkgs, ...}: let
  ##########################################################################
  #
  #  claude プラグイン — home-manager の programs.claude-code.plugins で宣言する。
  #
  #  ## なぜこの経路か（2026-10-18）
  #
  #  `/plugin install` は ~/.claude/settings.json の enabledPlugins に書く＝
  #  HM 非所有の可変ファイル（modules/apps/herdr/home.nix 参照）なので他機に
  #  伝播しない。programs.claude-code.plugins は各プラグインを
  #  ~/.claude/skills/<name> に symlink する「個人プラグイン」として読ませる
  #  （Claude Code 2.1.157+）ので、settings.json に一切触れずに宣言できる。
  #
  #  ★ 同モジュールの settings / marketplaces は使わないこと。使うと
  #    settings.json（と known_marketplaces.json）を store symlink で丸ごと
  #    所有し、settings.json 非所有の決定と衝突する。
  #
  #  ## package = null の理由
  #
  #  本体は home.nix が pkgsClaude.claude-code（nixpkgs-claude・`nhds` で bump）
  #  を入れている。ここで package を立てると二重インストールになるので null。
  #  null のとき HM は「最新版」とみなして personal-plugin 経路を使う。
  #
  #  ## 更新
  #
  #  rev 固定なので**放置すると永久に止まる**（claude-code 本体と同じ罠）。
  #  上げるときは：
  #    git ls-remote https://github.com/anthropics/claude-plugins-official HEAD
  #    nix flake prefetch github:anthropics/claude-plugins-official/<rev> --json
  #
  ##########################################################################
  claudePluginsOfficial = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-plugins-official";
    rev = "ea10b213686c90bb1984b2016937310e05336cf3";
    hash = "sha256-Tfs8Ig1rzLvaAuTZwqGUzKCK0TMWE2SddYss+H/04ug=";
  };
in {
  programs.claude-code = {
    enable = true;
    package = null;

    plugins = {
      # 自分のコードの脆弱性スキャン＋パッチ提案（Anthropic 公式）。
      # 多数のエージェントを fan-out するのでトークンを大きく食う。
      # 要 python3（PATH 上）。
      claude-security = "${claudePluginsOfficial}/plugins/claude-security";
    };
  };
}
