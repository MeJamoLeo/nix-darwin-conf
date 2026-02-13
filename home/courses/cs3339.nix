# CS 3339 - SSH configuration for TxState CS servers
{lib, ...}: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      eros = {
        hostname = "eros.cs.txstate.edu";
        user = "kif33";
        identityFile = "~/.ssh/id_ed25519_txstate";
        identitiesOnly = true;
        extraOptions.AddKeysToAgent = "yes";
      };
      zeus = {
        hostname = "zeus.cs.txstate.edu";
        user = "kif33";
        identityFile = "~/.ssh/id_ed25519_txstate";
        identitiesOnly = true;
        extraOptions.AddKeysToAgent = "yes";
      };
    };
  };

  home.activation.cs3339-ssh-reminder = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f "$HOME/.ssh/id_ed25519_txstate" ]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "CS 3339: SSH key not found! Generate one with:"
      echo "  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_txstate"
      echo ""
      echo "Then copy the public key to the server:"
      echo "  ssh-copy-id -i ~/.ssh/id_ed25519_txstate -o IdentitiesOnly=no -o PreferredAuthentications=keyboard-interactive,password kif33@eros.cs.txstate.edu"
      echo "  ssh-copy-id -i ~/.ssh/id_ed25519_txstate -o IdentitiesOnly=no -o PreferredAuthentications=keyboard-interactive,password kif33@zeus.cs.txstate.edu"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
    fi
  '';
}
