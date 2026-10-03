{
  config,
  pkgs,
  ...
}: {
  # mail-check — メールトリアージ（Gmail + TXST Outlook）の日次スイープを launchd から回す。
  # 実装は claude-obsidian の bin/mail-check.sh（`claude -p` を haiku で叩く headless ランナー）。
  # ここは「いつ・どの環境で呼ぶか」だけを宣言する。スクリプト本体は nix 管理にしない
  # （vault 側のプロンプト・設定と一体で更新されるため）。
  #
  # なぜ custom バケツか（modules/CLAUDE.md 判定）:
  #   価値の中心が自分のスクリプトの定期実行で、Claude Code 本体の設定ではない。
  #
  # ★ 2026-10-02 の発端：旧方式は SessionStart hook が「今日の digest が無い」と Claude に
  #   伝えて走らせる形だった（mail-digest-surface.sh）。**セッションを開かない日は走らない**ので
  #   9/20〜10/2 の12日間、誰も気づかないまま止まっていた。
  #   ★ 一般形＝**実行経路を人間（セッション）の任意呼び出しに置くと回らない。**
  #     record-blocks / todo-board と同じ結論で、定期実行は launchd に載せる。
  #
  # ⚠ RunAtLoad は false 固定。`switch` のたびに本物のスイープ（API 呼び出し・Gmail の
  #   ラベル付与・digest 上書き）が走るのを防ぐ。
  # ⚠ 起動時刻 06:00。Mac が寝ていて跨いだ場合、launchd は起床後に取りこぼし分を1回走らせる。
  # ⚠ mail-check.sh は引数を一切受け付けない（渡すと exit 64）。ProgramArguments は
  #   スクリプトパスのみ。
  # ⚠ PATH は最小の launchd 環境では `claude` が見つからない。mail-check.sh 自身は
  #   /opt/homebrew/bin 等を足すが nix の profile は足さないので、ここで明示する。
  #   python3 も verify 段で PATH から引かれるため、store パスの bin を先頭に置いて固定する。
  # ⚠ claude の認証は macOS keychain 経由（claude.ai コネクタ含む）。LaunchAgent は
  #   ユーザーの GUI セッションで動くので keychain に届く（LaunchDaemon にしないこと）。
  launchd.agents.mail-check = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "${config.home.homeDirectory}/Forge/claude-obsidian/bin/mail-check.sh"
      ];
      WorkingDirectory = "${config.home.homeDirectory}/Forge/claude-obsidian";
      StartCalendarInterval = [
        {
          Hour = 6;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        PATH = builtins.concatStringsSep ":" [
          "${pkgs.python3}/bin"
          "${config.home.profileDirectory}/bin"
          "/run/current-system/sw/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mail-check-launchd.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mail-check-launchd.err.log";
    };
  };
}
