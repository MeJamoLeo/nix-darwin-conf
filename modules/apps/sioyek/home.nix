# sioyek — 既定の PDF ビューア（mac・x1nano 共通。2026-10-23 に Skim から置き換え）。
#
# 選んだ理由：キー操作が vim 寄り（j/k・gg/G・/ 検索・m でマーク → ` で戻る）で、
# 参照（図・式・文献）へ飛んで戻るのが速い。Linux でも同じものが動くので設定を1か所にできる。
# キーは既定のままで vim 風なので、ここではいじらない（変えるなら programs.sioyek.bindings）。
#
# 既定アプリへの登録は「PDF の行だけ」を書き換える（他の関連付けは各 OS の持ち物のまま）：
#   mac   … modules/apps/file-defaults の duti（bundle id info.sioyek.sioyek）
#   Linux … 下の activation で xdg-mime（~/.config/mimeapps.list を丸ごと奪わない）
# LaTeX の表示・SyncTeX も sioyek（modules/domain/latex/home.nix の vimtex 設定）。
{
  lib,
  pkgs,
  ...
}: {
  programs.sioyek = {
    enable = true;
    # ⚠ macOS の一時回避（2026-10-23）：nixpkgs の sioyek（2.0.0-unstable-2026-09-24）は
    #   shaders/・keys.config・prefs.config・tutorial.pdf を .app の Contents/MacOS/ に置くが、
    #   本体は Contents/Resources/ を探す → シェーダが読めずページが真っ白、既定キーも無効。
    #   Resources 側から見えるように symlink を張る（本体が自分の実体パスから探すので、
    #   後付けのラッパーではなく overrideAttrs で .app 自体に入れる必要がある）。
    #   nixpkgs 側で直ったら package ごと外す。homebrew cask は Gatekeeper 不合格で
    #   2026-09-01 に無効化されているので逃げ先にならない。
    package =
      if pkgs.stdenv.hostPlatform.isDarwin
      then
        pkgs.sioyek.overrideAttrs (old: {
          postInstall =
            (old.postInstall or "")
            + ''
              c=$out/Applications/sioyek.app/Contents
              for f in shaders keys.config prefs.config tutorial.pdf; do
                if [ -e "$c/MacOS/$f" ] && [ ! -e "$c/Resources/$f" ]; then
                  ln -s "../MacOS/$f" "$c/Resources/$f"
                fi
              done
            '';
        })
      else pkgs.sioyek;
  };

  home.activation.sioyekPdfDefault = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${pkgs.xdg-utils}/bin/xdg-mime default sioyek.desktop application/pdf
    ''
  );
}
