{
  config,
  lib,
  pkgs,
  ...
}: let
  ##########################################################################
  #
  #  task-loop — Linear を状態の正本にした自動化のうち、Claude を呼ばない部分。
  #
  #  設計の正本は vault の task-execution-redesign-linear-orca §2026-10-31。
  #  役割の分け方：Orca automation ＝ Claude に考えさせる仕事だけ（無人 Agent issue）。
  #               launchd（ここ）＝ コードで済む仕事。ジョブごとに分ける（失敗の切り分け・
  #               間隔・必要な鍵が違うため）。共通部分は task_loop/ のライブラリ。
  #
  #  実行記録は ~/.local/state/task-loop/status/<job>.json（watchdog が最終成功時刻を見る）。
  #
  ##########################################################################
  home = config.home.homeDirectory;
  py = "${pkgs.python3}/bin/python3";
  # orca CLI は Orca.app の同梱品（nix 管理外）。launchd の PATH は最小なので絶対パスで渡す。
  orcaBin = "/Applications/Orca.app/Contents/Resources/bin/orca";
  env = {
    HOME = home;
    TASK_LOOP_ORCA = orcaBin;
    PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
  };
  job = name: extra:
    lib.recursiveUpdate {
      enable = true;
      config = {
        ProgramArguments = [py "${home}/bin/task-loop" name];
        EnvironmentVariables = env;
        RunAtLoad = false;
        StandardOutPath = "${home}/Library/Logs/task-loop-${name}.log";
        StandardErrorPath = "${home}/Library/Logs/task-loop-${name}.err.log";
      };
    }
    extra;
in {
  home.file."bin/task-loop" = {
    source = ./bin/task-loop;
    executable = true;
  };

  home.file.".local/lib/task-loop/task_loop".source = lib.cleanSourceWith {
    src = ./task_loop;
    filter = path: type: baseNameOf path != "__pycache__";
  };

  # workspace-cleanup：1日1回（朝 7:00）。Done/Canceled の issue のワークスペースを消し、
  #   Backlog/Todo のまま作業中のものを In Progress にする。
  #   ⚠ Mac が寝ていても、起床後に launchd が取りこぼし分を1回走らせる。
  #   ⚠ orca CLI は Orca.app の runtime が動いていないと失敗する → status に ok=false が残る。
  launchd.agents.task-loop-workspace-cleanup = job "workspace-cleanup" {
    config.StartCalendarInterval = [
      {
        Hour = 7;
        Minute = 0;
      }
    ];
  };
}
