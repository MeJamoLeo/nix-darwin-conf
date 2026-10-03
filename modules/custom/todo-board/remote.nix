{
  config,
  pkgs,
  ...
}: let
  # 母艦（ogasawara）の MagicDNS 名。env TODO_REMOTE_HOST で上書きできる（テスト・別名接続用）。
  remoteHost = "ogasawara.tailaaebcd.ts.net";

  # ogasawara の sshd ホスト鍵（/etc/ssh/ssh_host_ed25519_key.pub、2026-10-03 に実機で取得）。
  # ★ なぜここに宣言するか: 初回接続の "Are you sure you want to continue connecting?" を
  #   人間に答えさせない（switch 直後に手作業ゼロ、が要件）。かつ BatchMode=yes では
  #   プロンプトが出せず、未知ホストは即失敗するので、宣言が無いとそもそも繋がらない。
  # ⚠ ogasawara を再インストールするとホスト鍵が変わる。その時は StrictHostKeyChecking=yes が
  #   拒否するので、ここの鍵を差し替えて switch する（これは「なりすまし検知」が効いている状態）。
  hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAk5hP/G7zYwq7w3Q+3x5PDy9HnMPXY/trP/CbKoCF85";

  knownHosts = "${config.home.homeDirectory}/.ssh/known_hosts_todo";
  user = config.home.username;
  home = config.home.homeDirectory;
in {
  # todo-board のリモート版 — データ（~/Store）は ogasawara が唯一の正本なので、
  # 他機の `todo` は同期ではなく SSH で母艦の ~/bin/todo をそのまま叩く。
  # home.nix（本体）は ogasawara 専用。この module は「持っていない機体」に入れる。
  # ★ 同じ ~/bin/todo を作るので、ogasawara に import してはいけない（本体のラッパーと衝突する）。

  # 母艦のホスト鍵だけを書いた専用 known_hosts。ユーザーの ~/.ssh/known_hosts には触らない
  # （手書き・他ツールの内容と競合しない。home-manager が管理するので宣言＝実体）。
  # 接続先を IP や別名にしても検証できるよう、ホスト名は HostKeyAlias で固定する。
  home.file.".ssh/known_hosts_todo".text = ''
    ${remoteHost} ${hostKey}
  '';

  # ★ 鍵は固定しない: 既定の identity（tanegashima は ~/.ssh/id_ed25519。keys.nix の
  #   treo@tanegashima がその公開鍵で、ogasawara の authorizedKeys に入っている）に任せる。
  #   ssh-agent / Keychain もそのまま効く。
  #
  # 実装メモ（python にした理由）: 引数を「リモートの shell 向けに安全に」1個ずつ引用する必要がある
  #   （`todo add "a b; rm -rf ~"` が1引数のまま届く）。sh だけで書くと引用が壊れやすいので
  #   shlex.quote に任せる。ssh は引数を空白で連結して相手の login shell に渡すため、この引用が要る。
  # ・リモートの PATH: ssh の非対話 shell は PATH が最小で nvim/fzf が見つからない → 先頭に足す。
  #   `env PATH=…:$PATH` の $PATH は意図的に未引用（リモート側で展開させる）。
  # ・TERM: ghostty 等は xterm-ghostty を名乗り、リモートに terminfo が無いと TUI が死ぬ
  #   （modules/base/remote-access/darwin.nix の注記）ので xterm-256color に固定して渡す。
  # ・-t は stdin が TTY のときだけ（pick / edit は要る。`todo add` のパイプ・自動実行では付けない）。
  # ・BatchMode=yes: パスワード・確認プロンプトで固まらせない。ConnectTimeout=5: 母艦がスリープでも5秒で諦める。
  # ・TODO_BOARD_DIR は設定されているときだけ転送する（テスト用に母艦側の base を差し替えるため）。
  # ・ssh の失敗は終了コード 255。リモートの todo 自身の失敗（1/2）と区別して案内を出す。
  home.file."bin/todo" = {
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import os, shlex, subprocess, sys

      host = os.environ.get("TODO_REMOTE_HOST") or "${remoteHost}"
      path = "/etc/profiles/per-user/${user}/bin:/run/current-system/sw/bin"
      env = ["TERM=xterm-256color", "PATH=" + path + ":$PATH"]
      if os.environ.get("TODO_BOARD_DIR"):
          env.append("TODO_BOARD_DIR=" + shlex.quote(os.environ["TODO_BOARD_DIR"]))
      remote = "env " + " ".join(env) + " " + shlex.quote("${home}/bin/todo")
      remote += "".join(" " + shlex.quote(a) for a in sys.argv[1:])

      cmd = ["/usr/bin/ssh"]
      if sys.stdin.isatty():
          cmd.append("-t")
      cmd += [
          "-o", "BatchMode=yes",
          "-o", "ConnectTimeout=5",
          "-o", "LogLevel=ERROR",
          "-o", "StrictHostKeyChecking=yes",
          "-o", "UserKnownHostsFile=${knownHosts}",
          "-o", "HostKeyAlias=${remoteHost}",
          host, remote,
      ]
      rc = subprocess.call(cmd)
      if rc == 255:
          print("todo: ogasawara に繋がらない（Tailscale が切れてる / 母艦がスリープ / ホスト鍵が変わった？）: " + host, file=sys.stderr)
      sys.exit(rc)
    '';
  };
}
