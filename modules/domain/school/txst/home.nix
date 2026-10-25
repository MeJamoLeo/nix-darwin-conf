# Texas State University - 共通ユーザー設定
# - SSH (CS dept servers: eros / zeus / brooks / capi)
# - TxState 用 git identity (~/Store/20_Courses/ 以下で自動適用)
#
# ★ 2026-10-25: 作業場としての `~/txst/` を廃止した。
#   「学期中は ~/txst、終わったら ~/Store/20_Courses へ移す」という二段構えが、
#   実測で成立していなかった：Store 側に9科目 4.0GB があるのに対し ~/txst は
#   CS3360(0B) と CS4355(148K) の骨組みだけで、しかも CS4355 / CS3360 は
#   両方に存在していた（＝同じ授業の物が2箇所に割れた状態）。
#   2026-09-26 に `30_Work/cs4371` と `20_Courses/CS4355` の割れを片付けたのと
#   同じ失敗の再発なので、今回は入口を1つに倒した。
#   ★ 移動のひと手間を必要とする設計は、その手間が踏まれないと二重化になる。
#   授業の物は最初から `~/Store/20_Courses/<COURSE>/` に置く（Store の振り分け表 #2 のまま）。
#   実データの合流記録は `~/Store/MOVES-2026-10-25-txst.tsv`。
{lib, ...}: let
  txstIdentity = "~/.ssh/id_ed25519_txstate";

  # programs.ssh.settings は OpenSSH 本家のディレクティブ名 (HostName 等) を
  # そのまま使うフリーフォーム（HM 25.11+ で matchBlocks/extraOptions は deprecated）
  mkTxstHost = hostname: extra:
    {
      HostName = hostname;
      User = "kif33";
      IdentityFile = txstIdentity;
      IdentitiesOnly = "yes";
      AddKeysToAgent = "yes";
    }
    // extra;
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      eros = mkTxstHost "eros.cs.txstate.edu" {};
      zeus = mkTxstHost "zeus.cs.txstate.edu" {};
      brooks = mkTxstHost "eros.cs.txstate.edu" {
        RequestTTY = "yes";
        RemoteCommand = "ssh brooks";
      };
      capi = mkTxstHost "eros.cs.txstate.edu" {
        RequestTTY = "yes";
        RemoteCommand = "ssh capi";
      };
    };
  };

  # TxState 用 git identity。授業の作業場（Store/20_Courses/）配下の repo で自動適用。
  home.file.".gitconfig-txst".text = ''
    [user]
      name = Reo Tajiri
      email = kif33@txstate.edu
  '';

  programs.git.includes = [
    {
      path = "~/.gitconfig-txst";
      condition = "gitdir:~/Store/20_Courses/";
    }
  ];

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
