{
  username,
  nixvim,
  neru,
  ...
}: {
  # import sub modules
  imports = [
    ./shell.nix
    ./core.nix
    ./git.nix
    ./tmux.nix
    ./nixvim.nix
    ./starship.nix
    ./macos/aerospace.nix
    ./macos/chrome-anjin.nix
    ./wezterm.nix
    ./ghostty.nix
    ./cmux.nix
    ./herdr.nix
    ./cp
    ./claude.nix
    ./handy.nix
    ./neru.nix
    ./latex.nix
    ./school/txst.nix
    ./courses/cs3339.nix
    ./courses/cs3354.nix
    ((nixvim.homeModules or nixvim.homeManagerModules).nixvim)
    neru.homeManagerModules.default
  ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = {
    username = username;
    homeDirectory = "/Users/${username}";

    # This value determines the Home Manager release that your
    # configuration is compatible with. This helps avoid breakage
    # when a new Home Manager release introduces backwards
    # incompatible changes.
    #
    # You can update Home Manager without changing this value. See
    # the Home Manager release notes for a list of state version
    # changes in each release.
    stateVersion = "24.05";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # スクショ保存先 (system.nix screencapture.location) の存在保証。
  # ディレクトリが無いと macOS はスクリーンショットを黙って失敗させる。
  home.file."Downloads/screenshots/.keep".text = "";
}
