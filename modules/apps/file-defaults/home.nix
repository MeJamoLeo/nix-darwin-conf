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
#         pdf   → sioyek（設定は modules/apps/sioyek）
#         code  → Zed
#         svg   → LibreWolf（Chrome に吸われていた。画像はプレビューのまま）
#    2. noTunes … Music 起動ブロック + 差し替え先 IINA
#       （defaults だけではメディアキーの Music 起動は止められない）
#
#  前提:
#    - iina / notunes … homebrew-base casks → /Applications
#    - zed-editor / sioyek … nixpkgs（HM）→ ~/Applications/Home Manager Apps/<App>.app
#    初回 rebuild 直後は未導入のことがあるので存在チェックで no-op。
#
###################################################################################
let
  home = config.home.homeDirectory;

  iinaApp = "/Applications/IINA.app";
  iinaBundleId = "com.colliderli.iina";
  notunesApp = "/Applications/noTunes.app";
  sioyekApp = "${home}/Applications/Home Manager Apps/sioyek.app";
  sioyekBundleId = "info.sioyek.sioyek";
  # Dock persistent-apps と同じ HM Apps パス（modules/base/macos-defaults）
  zedApp = "${home}/Applications/Home Manager Apps/Zed.app";
  zedBundleId = "dev.zed.Zed";
  # nix-darwin（system 側）の Nix Apps。youtube-gate が入れている（modules/custom/youtube-gate）。
  # bundle id は上流の io.gitlab.librewolf-community ではなく nixpkgs ラッパーの org.nixos.librewolf。
  librewolfApp = "/Applications/Nix Apps/LibreWolf.app";
  librewolfBundleId = "org.nixos.librewolf";

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

  # stderr は握り潰す：Zed の Info.plist で未宣言の拡張子（.mk / .dockerfile /
  # .gitignore / .env / .ini / .cfg / .conf 等）は macOS が動的 UTI (dyn.ah62d...)
  # に落として LaunchServices が error -50 (paramErr) を返す。動作影響は無いが
  # switch ログが騒がしくなるので黙らせる。成功した拡張子は正しく紐付いてる。
  dutiSet = bundleId: extensions:
    lib.concatMapStringsSep "\n" (
      ext: ''$DUTI -s ${bundleId} .${ext} all 2>/dev/null || true''
    )
    extensions;
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

  home.activation.fileDefaultsDuti = lib.hm.dag.entryAfter ["writeBoundary"] ''
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

    # --- pdf → sioyek ---
    # nix 由来の .app は初回 switch の時点で LaunchServices に未登録のことがあり、その状態の
    # duti -s は黙って効かない（2026-10-23 に踏んだ：switch 後も pdf → Skim のままだった）。
    # 先に lsregister で知らせてから既定にする。
    if [ -d "${sioyekApp}" ]; then
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${sioyekApp}" || true
      $DUTI -s ${sioyekBundleId} .pdf all || true
      echo "file-defaults: pdf → ${sioyekBundleId}"
    else
      echo "file-defaults: sioyek not at ${sioyekApp}; skip pdf"
    fi

    # --- svg → LibreWolf ---
    if [ -d "${librewolfApp}" ]; then
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${librewolfApp}" || true
      $DUTI -s ${librewolfBundleId} .svg all || true
      echo "file-defaults: svg → ${librewolfBundleId}"
    else
      echo "file-defaults: LibreWolf not at ${librewolfApp}; skip svg"
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
