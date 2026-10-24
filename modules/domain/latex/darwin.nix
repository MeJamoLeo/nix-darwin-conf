# LaTeX 関連のシステム側インストール。
# Neovim から使う設定 (vimtex, keymap, texlab, 雛形挿入) は同ディレクトリの home.nix に分離。
# PDF ビューアは sioyek（modules/apps/sioyek・2026-10-23 に Skim から移行）。
# vimtex の view_method も sioyek（home.nix）。
{...}: {
  homebrew = {
    brews = [
      "texlive" # LaTeX distribution
    ];
  };
}
