# LaTeX 関連のシステム側インストール。
# Neovim から使う設定 (vimtex, keymap, texlab, 雛形挿入) は home/latex.nix に分離。
{...}: {
  homebrew = {
    brews = [
      "texlive" # LaTeX distribution
    ];
    casks = [
      "skim" # PDF viewer with SyncTeX support
    ];
  };
}
