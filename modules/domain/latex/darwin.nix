# LaTeX 関連のシステム側インストール。
# Neovim から使う設定 (vimtex, keymap, texlab, 雛形挿入) は同ディレクトリの home.nix に分離。
# skim は PDF 既定ビューアとして homebrew-base + file-defaults へ昇格済み。
# vimtex の view_method = "skim" はそのまま（アプリ本体は基地側が供給）。
{...}: {
  homebrew = {
    brews = [
      "texlive" # LaTeX distribution
    ];
  };
}
