{
  lib,
  pkgs,
  config,
  ...
}:
###################################################################################
#
#  file-defaults — Finder「このアプリケーションで開く」の宣言的既定。
#
#  系統:
#    1. duti … 拡張子 → 既定アプリ（Get Info → すべて変更 の宣言版）
#         audio → IINA
#         pdf   → Skim
#         code  → Zed
#    2. noTunes … Music 起動ブロック + 差し替え先 IINA
#       （defaults だけではメディアキーの Music 起動は止められない）
#
#  前提:
#    - iina / notunes / skim … homebrew-base casks → /Applications
#    - zed-editor … home.packages (core-packages) → ~/Applications/Home Manager Apps/Zed.app
#    初回 rebuild 直後は未導入のことがあるので存在チェックで no-op。
#
###################################################################################
let
  home = config.home.homeDirectory;

  iinaApp = "/Applications/IINA.app";
  iinaBundleId = "com.colliderli.iina";
  notunesApp = "/Applications/noTunes.app";
  skimApp = "/Applications/Skim.app";
  skimBundleId = "net.sourceforge.skim-app.skim";
  # Dock persistent-apps と同じ HM Apps パス（modules/base/macos-defaults）
  zedApp = "${home}/Applications/Home Manager Apps/Zed.app";
  zedBundleId = "dev.zed.Zed";

  audioExtensions = [
    "mp3"
    "m4a"
    "flac"
    "wav"
    "aac"
    "ogg"
    "opus"
    "aiff"
    "aif"
    "wma"
    "alac"
  ];

  # ソース / 設定。Xcode や IINA(.ts) に吸われていたものを Zed へ。
  # .html はブラウザ既定のまま（触らない）。
  codeExtensions = [
    "c"
    "cc"
    "cpp"
    "cxx"
    "h"
    "hh"
    "hpp"
    "hxx"
    "m"
    "mm"
    "swift"
    "py"
    "rb"
    "pl"
    "pm"
    "go"
    "rs"
    "java"
    "kt"
    "kts"
    "js"
    "jsx"
    "ts"
    "tsx"
    "mjs"
    "cjs"
    "css"
    "scss"
    "sass"
    "less"
    "json"
    "jsonc"
    "md"
    "mdx"
    "txt"
    "toml"
    "yaml"
    "yml"
    "xml"
    "nix"
    "lua"
    "vim"
    "sh"
    "bash"
    "zsh"
    "fish"
    "sql"
    "graphql"
    "gql"
    "proto"
    "cmake"
    "make"
    "mk"
    "dockerfile"
    "editorconfig"
    "gitignore"
    "env"
    "ini"
    "cfg"
    "conf"
  ];

  dutiSet = bundleId: extensions:
    lib.concatMapStringsSep "\n" (
      ext: ''$DUTI -s ${bundleId} .${ext} all || true''
    ) extensions;
in {
  home.packages = [pkgs.duti];

  # noTunes: Music 起動時の差し替え先 = IINA
  targets.darwin.defaults."digital.twisted.noTunes" = {
    replacement = iinaApp;
  };

  # ログイン時 noTunes（Login Items の宣言的代替）。KeepAlive なし。
  launchd.agents."com.treo.notunes" = {
    enable = true;
    config = {
      Label = "com.treo.notunes";
      ProgramArguments = [
        "/bin/bash"
        "-c"
        "if [ -d '${notunesApp}' ]; then /usr/bin/open -ga noTunes; fi"
      ];
      RunAtLoad = true;
    };
  };

  home.activation.fileDefaultsDuti =
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      DUTI="${pkgs.duti}/bin/duti"
      if [ ! -x "$DUTI" ]; then
        echo "file-defaults: duti missing at $DUTI; skip"
        exit 0
      fi

      # --- audio → IINA ---
      if [ -d "${iinaApp}" ]; then
        ${dutiSet iinaBundleId audioExtensions}
        echo "file-defaults: audio → ${iinaBundleId}"
      else
        echo "file-defaults: IINA not at ${iinaApp}; skip audio"
      fi

      # --- pdf → Skim ---
      if [ -d "${skimApp}" ]; then
        $DUTI -s ${skimBundleId} .pdf all || true
        echo "file-defaults: pdf → ${skimBundleId}"
      else
        echo "file-defaults: Skim not at ${skimApp}; skip pdf"
      fi

      # --- code → Zed ---
      if [ -d "${zedApp}" ]; then
        ${dutiSet zedBundleId codeExtensions}
        echo "file-defaults: code → ${zedBundleId}"
      else
        echo "file-defaults: Zed not at ${zedApp}; skip code"
      fi
    '';
}
