# CS 3339 - Common Lisp 開発環境
# TxState CS サーバへの SSH 設定は home/school/txst.nix を参照
{pkgs, ...}: {
  home.packages = with pkgs; [
    poppler-utils # PDF tools (pdftotext, pdfinfo, etc.)
    sbcl # Steel Bank Common Lisp
  ];

  programs.nixvim = {
    extraPlugins = [
      (pkgs.vimUtils.buildVimPlugin {
        name = "vlime";
        src = pkgs.fetchFromGitHub {
          owner = "vlime";
          repo = "vlime";
          rev = "e276e9a6f37d2699a3caa63be19314f5a19a1481";
          hash = "sha256-tCqN80lgj11ggzGmuGF077oqL5ByjUp6jVmRUTrIWJA=";
        };
      })
    ];
    globals.vlime_cl_impl = "sbcl";
  };
}
