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

  # completion-check は bin/task-loop（ジョブ振り分け）を経由しない単独の入口。
  home.file."bin/task-loop-completion-check" = {
    source = ./bin/task-loop-completion-check;
    executable = true;
  };

  # inventory（自動化の棚卸し）も単独の入口。
  home.file."bin/task-loop-inventory" = {
    source = ./bin/task-loop-inventory;
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

  # completion-check：3時間ごと。Canvas で提出済み（0 点なら Canceled）の課題に対応する
  #   Linear issue と子を閉じる。取りこぼしは次の回で拾うので RunAtLoad は不要。
  #   ⚠ Canvas のトークンは Keychain（canvas-txst-token）から読む。ロック中だと失敗し status に ok=false が残る。
  launchd.agents.task-loop-completion-check = job "completion-check" {
    config = {
      ProgramArguments = [py "${home}/bin/task-loop-completion-check" "--apply"];
      StartInterval = 10800;
    };
  };

  # inventory：毎朝 7:30。動いている自動化の一覧と不調を Linear の常設 issue（LIF）に書き直す。
  #   不調があれば Todo＋期限今日、無ければ Backlog＋期限なし。取りこぼしは翌朝直るので RunAtLoad は不要。
  #   ⚠ orca CLI は Orca.app の runtime が動いていないと失敗する → status に ok=false が残る。
  launchd.agents.task-loop-inventory = job "inventory" {
    config = {
      ProgramArguments = [py "${home}/bin/task-loop-inventory" "--apply"];
      StartCalendarInterval = [
        {
          Hour = 7;
          Minute = 30;
        }
      ];
    };
  };
}
