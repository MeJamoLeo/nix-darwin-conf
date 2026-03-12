# CS 3339 - Common Lisp dev environment & SSH configuration for TxState CS servers
{
  pkgs,
  lib,
  ...
}: {
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
      brooks = {
        hostname = "eros.cs.txstate.edu";
        user = "kif33";
        identityFile = "~/.ssh/id_ed25519_txstate";
        identitiesOnly = true;
        extraOptions = {
          RequestTTY = "yes";
          RemoteCommand = "ssh brooks";
        };
      };
      capi = {
        hostname = "eros.cs.txstate.edu";
        user = "kif33";
        identityFile = "~/.ssh/id_ed25519_txstate";
        identitiesOnly = true;
        extraOptions = {
          RequestTTY = "yes";
          RemoteCommand = "ssh capi";
        };
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
