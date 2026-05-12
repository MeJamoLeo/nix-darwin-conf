# Texas State University - 共通ユーザー設定
# - SSH (CS dept servers: eros / zeus / brooks / capi)
# - TxState 用 git identity (~/txst/ 以下で自動適用)
# - ~/txst/ ディレクトリ作成
{lib, ...}: let
  txstIdentity = "~/.ssh/id_ed25519_txstate";

  mkTxstHost = {
    hostname,
    extraOptions ? {},
  }: {
    inherit hostname;
    user = "kif33";
    identityFile = txstIdentity;
    identitiesOnly = true;
    extraOptions = {AddKeysToAgent = "yes";} // extraOptions;
  };
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      eros = mkTxstHost {hostname = "eros.cs.txstate.edu";};
      zeus = mkTxstHost {hostname = "zeus.cs.txstate.edu";};
      brooks = mkTxstHost {
        hostname = "eros.cs.txstate.edu";
        extraOptions = {
          RequestTTY = "yes";
          RemoteCommand = "ssh brooks";
        };
      };
      capi = mkTxstHost {
        hostname = "eros.cs.txstate.edu";
        extraOptions = {
          RequestTTY = "yes";
          RemoteCommand = "ssh capi";
        };
      };
    };
  };

  # TxState 用 git identity。~/txst/ 配下のリポジトリで自動適用。
  home.file.".gitconfig-txst".text = ''
    [user]
      name = Reo Tajiri
      email = kif33@txstate.edu
  '';

  programs.git.includes = [
    {
      path = "~/.gitconfig-txst";
      condition = "gitdir:~/txst/";
    }
  ];

  # ~/txst/ 親ディレクトリ作成。各科目はこの下にサブディレクトリを作る。
  home.activation.txst-setup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/txst"
  '';

  # SSH 鍵が無ければ生成手順を表示
  home.activation.txst-ssh-reminder = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f "$HOME/.ssh/id_ed25519_txstate" ]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "TxState: SSH key not found! Generate one with:"
      echo "  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_txstate"
      echo ""
      echo "Then copy the public key to the servers:"
      echo "  ssh-copy-id -i ~/.ssh/id_ed25519_txstate -o IdentitiesOnly=no -o PreferredAuthentications=keyboard-interactive,password kif33@eros.cs.txstate.edu"
      echo "  ssh-copy-id -i ~/.ssh/id_ed25519_txstate -o IdentitiesOnly=no -o PreferredAuthentications=keyboard-interactive,password kif33@zeus.cs.txstate.edu"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
    fi
  '';
}
