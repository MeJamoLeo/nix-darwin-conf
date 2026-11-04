# Karabiner-Elements 本体（cask）。ルールは同じディレクトリの home.nix。
# nixpkgs は 15.7.0 で cask は 16.3.0。macOS 26/27 のドライバ周りは新しい方を採る。
# 入れる理由（Option+HJKL の Secure Input 対策・EarPods のリモコン）は home.nix 冒頭。
{
  homebrew.casks = ["karabiner-elements"];
}
