{
  config,
  lib,
  pkgs,
  ...
}: {
  # job-watch — 新卒（OPT）／インターン・co-op（CPT）求人の日次ウォッチ。
  # 取得元は SimplifyJobs の listings.json 2本と Oracle Recruiting Cloud の公開 API。
  # 場所（オースティン周辺 > TX > リモート）・題名・学位で足切りし、新着だけ本文を取りに行って
  # F-1／OPT／CPT の扱いを正規表現で分類する（EXCLUDE は出力から落とす）。
  # 出力は ~/Store/30_Work/job-hunt-2027/job-watch/YYYY/YYYYMMDD-jobs.md、既報は同 .state.json。
  # 新着があれば todo の backlog に「見る」を1行足す（~/bin/todo add 経由）。
  #
  # 実装は ./job_watch/（python3 パッケージ・標準ライブラリのみ）、./bin/job-watch はそれを呼ぶだけの薄い起動役。
  # todo-board と同じ配置（パッケージは ~/.local/lib/job-watch、起動役は ~/bin）。
  # __pycache__ は store に入れない（flake 評価に作業ツリーの pycache が混ざらないように）。
  home.file."bin/job-watch" = {
    source = ./bin/job-watch;
    executable = true;
  };

  home.file.".local/lib/job-watch/job_watch".source = lib.cleanSourceWith {
    src = ./job_watch;
    filter = path: type: baseNameOf path != "__pycache__";
  };

  # 毎朝 07:00。todo-board の roll（06:00）の後に走るので、backlog に足した1行は翌朝の振り分けではなく
  # 当日分として次の roll／sync に拾われる。
  #   ⚠ RunAtLoad は false 固定。switch のたびに外部 API を叩かない（mail-check と同じ）。
  #   ⚠ python は store パス固定、PATH は明示（launchd の PATH は最小）。~/bin を足すのは `todo` を引くため。
  #   ⚠ ネットワーク断は source ごとに握ってフッタに残す。launchd 側のエラーログには出ない。
  #   ⚠ Mac が 07:00 に寝ていても、起床後に launchd が取りこぼし分を1回走らせる。
  launchd.agents.job-watch = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "${config.home.homeDirectory}/bin/job-watch"
        "run"
      ];
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        PATH = builtins.concatStringsSep ":" [
          "${pkgs.python3}/bin"
          "${config.home.homeDirectory}/bin"
          "${config.home.profileDirectory}/bin"
          "/run/current-system/sw/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      };
      StartCalendarInterval = [
        {
          Hour = 7;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/job-watch-launchd.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/job-watch-launchd.err.log";
    };
  };
}
