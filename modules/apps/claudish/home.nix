{pkgs, ...}: let
  ##########################################################################
  #
  #  claudish-to-english — Claude の返信を、ローカル LLM（ollama）で平易な文に
  #  書き直して表示する plugin（MessageDisplay hook）。表示だけを変え、
  #  transcript と Claude 側の文脈は原文のまま。失敗時は原文を出す（fail-open）。
  #  https://github.com/gvzdv/claudish-to-english
  #
  #  ## ogasawara 限定（2026-10-27）
  #
  #  ollama とモデル（qwen2.5:14b）がこの機体にしか無いので、profile に入れず
  #  hosts/ogasawara.nix からだけ import する。他機で有効にしても fail-open で
  #  何もしないが、配る意味も無い。
  #
  #  ## 経路
  #
  #  plugins.nix と同じ programs.claude-code.plugins（personal plugin・
  #  settings.json に触れない）。attrset なので plugins.nix の宣言とマージされる。
  #
  #  ## 既定は off・使うときだけ on
  #
  #  on/off は ~/.claude/claudish-off（フラグファイル）で切り替わる。
  #  `/claudish on` はこのファイルを消すだけなので、CLAUDISH_ENABLED=0 で
  #  止めると on に戻せなくなる。だから止めるのはフラグファイルでやる。
  #  モデルと表示方式は下の sessionVariables で渡す。hook は claude を起動した
  #  shell の env を継承する。settings.json の env に置かないのは、HM 非所有の
  #  手動ファイルに機体限定の設定を散らさないため。
  #
  #  ## 更新
  #
  #  rev 固定。上げるときは：
  #    git ls-remote https://github.com/gvzdv/claudish-to-english HEAD
  #    nix flake prefetch github:gvzdv/claudish-to-english/<rev> --json
  #
  ##########################################################################
  claudish = pkgs.fetchFromGitHub {
    owner = "gvzdv";
    repo = "claudish-to-english";
    rev = "346702bbe0aaaae08cb45e8959c11a55cd476f88"; # v0.10.0
    hash = "sha256-Aypqr+2SUKrLdxvfVJVq6QPFH3TjY+6o3mXAe9DiKSE=";
  };
in {
  programs.claude-code.plugins.claudish-to-english = "${claudish}";

  home.sessionVariables = {
    CLAUDISH_MODEL = "qwen2.5:14b"; # 既に pull 済み。既定の gemma4:26b-mlx は未取得
    CLAUDISH_MODE = "replace"; # 書き直しだけを表示。原文は /claudish last
  };
}
