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

  #--- 読み取り専用ミラー（caldash の todo ペイン用）--------------------------------
  # ★ これは「同期」ではない。書き手は ogasawara 1台のまま（上の方針どおり）で、tanegashima は
  #   今日の日次ファイル1枚を一方向にコピーして持つだけ。書き戻す経路が無いので、
  #   2台で編集が衝突して片方が消える、という同期特有の事故は構造的に起きない（避けたかったのはそれ）。
  #   なので ~/.cache/todo-mirror/ は読むだけの場所で、`todo`（SSH ラッパー）が引き続き唯一の編集口。
  # ★ push でなく pull にした理由: tanegashima はスリープするノート。ogasawara から押す方式だと
  #   寝ている相手には届かず、起きた後に押し直す仕組みも要る。pull なら launchd が
  #   StartInterval を逃しても復帰後に自分で1回走らせる（取りこぼしを自然に回収できる）。
  # ★ 5 分間隔: ユーザー決定（2026-10-03）。todo は分単位で変わる物ではなく、ssh 1回は軽い。
  #   鮮度が落ちたときは caldash が .synced の mtime を見て面に警告を出す（下の env）。
  # ・取得先は「今日のファイル、まだ無ければ（06:00 の roll 前）それ以前で最新」。相対パス
  #   YYYY/YYYYMMDD-todo.md を1行目に、本文をその後に出させ、同じ相対パスでミラーに置く
  #   （caldash 側の「今日→無ければ最新の過去」ロジックがそのまま効く）。
  # ・書き込みは tmp → os.replace（読む側が半端なファイルを見ない）。3 日より古い日次は掃除する
  #   （ただし今回取得した物は消さない＝母艦が何日も落ちていても最後の1枚は残る）。
  # ・失敗（ssh 255・ファイル無し）は前回のコピーを触らず stderr に残して非 0 で終わる。
  # ・env: TODO_REMOTE_HOST（接続先上書き）/ TODO_MIRROR_DIR（置き場上書き。テスト用）/
  #   TODO_BOARD_DIR（母艦側 base の差し替え。テスト用）。
  home.file."bin/todo-mirror" = {
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import datetime as dt, os, re, shlex, subprocess, sys, tempfile

      host = os.environ.get("TODO_REMOTE_HOST") or "${remoteHost}"
      mirror = os.environ.get("TODO_MIRROR_DIR") or "${home}/.cache/todo-mirror"
      REL = re.compile(r"^(\d{4})/(\d{8})-todo\.md$")
      KEEP_DAYS = 3

      # 母艦側で走らせる sh。ssh は login shell(zsh) に渡すので POSIX の範囲だけ使う。
      # base は todo-board と同じ規則（env TODO_BOARD_DIR → ~/Store/30_Work/todo）。
      # 日付が today 以下で最新の1枚を選び、1行目=相対パス、2行目以降=本文。
      remote_sh = """
      base=$TODO_BOARD_DIR; [ -n "$base" ] || base=$HOME/Store/30_Work/todo
      today=$(date +%Y%m%d)
      f=$(ls "$base"/[0-9][0-9][0-9][0-9]/[0-9]*-todo.md 2>/dev/null | awk -F/ -v t="$today" 'substr($NF,1,8)<=t' | sort | tail -n 1)
      [ -n "$f" ] || exit 3
      printf '%s\\n' "$f" | sed "s|^$base/||"
      cat "$f"
      """
      path = "/etc/profiles/per-user/${user}/bin:/run/current-system/sw/bin"
      env = ["PATH=" + path + ":$PATH"]
      if os.environ.get("TODO_BOARD_DIR"):
          env.append("TODO_BOARD_DIR=" + shlex.quote(os.environ["TODO_BOARD_DIR"]))
      remote = "env " + " ".join(env) + " sh -c " + shlex.quote(remote_sh)

      cmd = [
          "/usr/bin/ssh",
          "-o", "BatchMode=yes",
          "-o", "ConnectTimeout=5",
          "-o", "LogLevel=ERROR",
          "-o", "StrictHostKeyChecking=yes",
          "-o", "UserKnownHostsFile=${knownHosts}",
          "-o", "HostKeyAlias=${remoteHost}",
          host, remote,
      ]

      def log(msg):
          print(dt.datetime.now().strftime("%F %T") + " todo-mirror: " + msg, file=sys.stderr)

      def main():
          try:
              r = subprocess.run(cmd, capture_output=True, timeout=30)
          except subprocess.TimeoutExpired:
              log("ssh timeout（前回のコピーを残す）")
              return 1
          if r.returncode != 0:
              why = "ogasawara に繋がらない" if r.returncode == 255 else "リモートの取得が失敗 rc=%d" % r.returncode
              log(why + "（前回のコピーを残す）: " + r.stderr.decode("utf-8", "replace").strip())
              return 1
          head, sep, body = r.stdout.partition(b"\n")
          m = REL.match(head.decode("utf-8", "replace"))
          if not sep or not m:
              log("相対パスが不正（前回のコピーを残す）: %r" % head[:80])
              return 1
          rel = head.decode()
          dest = os.path.join(mirror, rel)
          os.makedirs(os.path.dirname(dest), exist_ok=True)
          fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dest), prefix=".mirror-")
          try:
              with os.fdopen(fd, "wb") as f:
                  f.write(body)
              os.replace(tmp, dest)
          except BaseException:
              if os.path.exists(tmp):
                  os.unlink(tmp)
              raise
          # 掃除: 3 日より古い日次（今回の1枚は除く）
          cutoff = (dt.date.today() - dt.timedelta(days=KEEP_DAYS)).strftime("%Y%m%d")
          for y in os.listdir(mirror):
              yd = os.path.join(mirror, y)
              if not (len(y) == 4 and y.isdigit() and os.path.isdir(yd)):
                  continue
              for n in os.listdir(yd):
                  p = os.path.join(yd, n)
                  if p != dest and re.match(r"^\d{8}-todo\.md$", n) and n[:8] < cutoff:
                      os.unlink(p)
          # 最終成功時刻 = .synced の mtime（caldash の鮮度警告が読む）
          sp = os.path.join(mirror, ".synced")
          with open(sp, "a"):
              pass
          os.utime(sp, None)
          return 0

      sys.exit(main())
    '';
  };

  launchd.agents.todo-mirror = {
    enable = true;
    config = {
      ProgramArguments = ["${home}/bin/todo-mirror"];
      RunAtLoad = true; # switch 直後・ログイン直後に即1回（5 分待たせない）
      StartInterval = 300;
      StandardOutPath = "${home}/Library/Logs/todo-mirror.log";
      StandardErrorPath = "${home}/Library/Logs/todo-mirror.err.log";
    };
  };

  # caldash（共有モジュール）にミラーを読ませる。ogasawara では未設定＝~/Store を直読み・鮮度警告なし。
  # 15 分 = 同期間隔 5 分の 3 回ぶん。1〜2 回の取りこぼし（スリープ復帰直後等）では警告を出さない。
  # launchd.agents.<name>.config の EnvironmentVariables は attrs 型なので、module 間で自動マージされる。
  launchd.agents."com.treo.calendar-dashboard-live".config.EnvironmentVariables = {
    CALDASH_TODO_DIR = "${home}/.cache/todo-mirror";
    CALDASH_TODO_STALE_MIN = "15";
  };
}
