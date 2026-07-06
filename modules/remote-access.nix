{
  pkgs,
  username,
  ...
}: let
  # デバイス公開鍵台帳(単一源)。鍵の追加・失効は keys.nix 側で行う。
  keys = import ../keys.nix;
in {
  ##########################################################################
  #
  #  Remote access: iPhone/Mac → Tailscale → ssh/mosh → この Mac
  #
  #  設計・使い分け・リスク評価は vault の remote-access-usecases 参照。
  #  導入方式は OSS 版 tailscaled(nix-darwin services.tailscale)を採用:
  #  宣言的管理 + Tailscale SSH 可(GUI cask 版は sandbox 内だが SSH 不可)。
  #
  #  rebuild 後に一度だけ手動:
  #    sudo tailscale up --ssh   # SSO ログイン(ブラウザが開く)
  #  以後は daemon が自動起動。ACL / key expiry は admin console 側で設定。
  #
  ##########################################################################

  # tailscaled を launchd daemon として常駐。CLI(pkgs.tailscale)も
  # module が environment.systemPackages に追加してくれる。
  services.tailscale.enable = true;

  # この pin ではバイナリキャッシュ未hitでソースビルドになり、
  # net/netns のテストが nix sandbox のネットワーク制約で落ちるためスキップ。
  # キャッシュに乗る pin へ更新したら外してよい。
  services.tailscale.package = pkgs.tailscale.overrideAttrs (_: {doCheck = false;});

  # mosh: サーバ側実体は mosh-server。/etc/zshenv が nix-darwin の
  # set-environment を全シェル(ssh の非対話 exec 含む)で読むため、
  # systemPackages に置けばクライアントから `mosh <host>` だけで見つかる。
  # 見つからない端末アプリからは --server=/run/current-system/sw/bin/mosh-server。
  #
  # ghostty-bin.terminfo: Ghostty は TERM=xterm-ghostty を名乗るが、nix の
  # mosh/ncurses が引く terminfo DB に定義が無いと mosh が起動時に死ぬ
  # ("'xterm-ghostty': unknown terminal type"、tanegashima で実機確認)。
  # terminfo 定義だけの出力を systemPackages に置くと
  # /run/current-system/sw/share/terminfo に入り、TERMINFO_DIRS 経由で
  # クライアント側 mosh・サーバ側 TUI の双方から解決できる。
  environment.systemPackages = [
    pkgs.mosh
    pkgs.ghostty-bin.terminfo
  ];

  # Remote Login(sshd)を宣言的に ON に保つ(有効済みなら no-op)。
  # systemsetup -setremotelogin は Full Disk Access を要求するので launchctl で。
  system.activationScripts.postActivation.text = ''
    if ! /bin/launchctl print system/com.openssh.sshd > /dev/null 2>&1; then
      echo "enabling Remote Login (sshd)..."
      /bin/launchctl load -w /System/Library/LaunchDaemons/ssh.plist
    fi
  '';

  # sshd 硬化: 公開鍵認証のみ(パスワード・キーボード対話を閉じる)。
  # macOS の sshd_config は /etc/ssh/sshd_config.d/* を先頭で Include し、
  # sshd は「最初に現れた値が勝つ」。既存 drop-in(100-macos / 100-nix-darwin /
  # 101-authorized-keys)はこの 2 項目を設定しないため、名前順は影響しない。
  # 注意: Tailscale SSH(up --ssh)経由の接続は tailscaled が処理するので
  # この設定の影響を受けない(iPhone からの初回接続はそちらで入れる)。
  environment.etc."ssh/sshd_config.d/200-remote-access.conf".text = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';

  # 鍵は nix-darwin の AuthorizedKeysCommand 機構(/etc/ssh/nix_authorized_keys.d)
  # で宣言配布。~/.ssh/authorized_keys への手動追記も併用可(AuthorizedKeysFile は
  # デフォルトのまま生きている)。
  # このホストに入ってよいデバイスを keys.nix の台帳から明示的に選ぶ
  # (全許可 attrValues ではなく名前で列挙 = git 上で読める ACL)。
  users.users.${username}.openssh.authorizedKeys.keys = [
    keys.ogasawara
    keys.tanegashima
    # keys.iphone-blink   # Blink で鍵を生成したら台帳に登録して有効化
  ];
}
