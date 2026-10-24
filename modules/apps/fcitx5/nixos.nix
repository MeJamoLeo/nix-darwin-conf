# 日本語入力（fcitx5 + mozc）。Wayland フロントエンドで niri 上の全アプリに効かせる。
{pkgs, ...}: {
  # ⚠ 一時回避（2026-10-23）：nixos-unstable の Qt の uic が、.ui のクラス名の先頭 `::`
  #   （`::mozc::gui::DictionaryContentTableWidget`）を "Invalid class name" で拒否するように
  #   なり、mozc（＝fcitx5-mozc）のビルドが落ちる。先頭の `::` を外すだけのパッチ
  #   （同じ名前空間を指すので意味は変わらない）。上流 mozc / nixpkgs で直ったらこの overlay を消す。
  nixpkgs.overlays = [
    (_: prev: {
      mozc = prev.mozc.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            find . -name '*.ui' -exec sed -i 's/"::mozc::/"mozc::/g; s/>::mozc::/>mozc::/g' {} +
          '';
      });
    })
  ];

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [fcitx5-mozc fcitx5-gtk];
      settings.inputMethod = {
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "mozc";
        };
        "Groups/0/Items/0" = {
          Name = "keyboard-us";
          Layout = "";
        };
        "Groups/0/Items/1" = {
          Name = "mozc";
          Layout = "";
        };
        GroupOrder."0" = "Default";
      };
    };
  };
}
