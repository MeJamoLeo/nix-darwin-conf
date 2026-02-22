{pkgs, ...}: {
  programs.ghostty = {
    enable = true;
    package = null;
    settings = {
      font-size = 13;
      theme = "Kasugano";
      background-opacity = 0.8;
      background-blur-radius = 20;
      macos-titlebar-style = "hidden";
      keybind = [
        "super+d=new_split:right"
        "super+shift+d=new_split:down"
        "super+w=close_surface"
        "super+j=goto_split:next"
        "super+ctrl+h=resize_split:left,50"
        "super+ctrl+l=resize_split:right,50"
        "super+ctrl+k=resize_split:up,50"
        "super+ctrl+j=resize_split:down,50"
      ];
    };
  };
}
