# cp-print — NoviSteps の AtCoder 問題を印刷用 PDF にする（x1nano 専用）。
# 旧 nixos-cp の modules/cp-print.nix と tools/cp-print-build を 2026-10-23 にここへ移した。
# スクリプト本体は同居の print_atcoder.py。旧版は repo の checkout を実行時に辿っていたが、
# いまは store に固めて `cp-print-build` として配る。
{pkgs, ...}: let
  texEnv = pkgs.texlive.combine {
    inherit
      (pkgs.texlive)
      scheme-small
      collection-fontsrecommended
      collection-langjapanese
      collection-xetex
      xecjk
      fancyhdr
      geometry
      hyperref
      enumitem
      titlesec
      pgf
      eso-pic
      etoolbox
      anyfontsize
      ulem
      ;
  };
  py = pkgs.python3.withPackages (ps: [ps.beautifulsoup4]);
  cpPrintBuild = pkgs.writeShellScriptBin "cp-print-build" ''
    exec ${py}/bin/python3 ${./print_atcoder.py} "$@"
  '';
in {
  environment.systemPackages = [
    cpPrintBuild
    texEnv
    pkgs.pandoc
    pkgs.poppler-utils
    pkgs.qpdf
  ];

  # noto-fonts-cjk-sans は可変軸 OTC で xdvipdfmx/luatex が埋め込めない（loca table not found）。
  # 静的な日本語フォントを足す。
  fonts.packages = with pkgs; [ipaexfont dejavu_fonts];

  environment.sessionVariables.CP_PRINT_OUTPUT_DIR = "$HOME/workspace/novisteps_prints";
}
