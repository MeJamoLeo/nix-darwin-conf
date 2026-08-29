{
  config,
  pkgs,
  ...
}: {
  # earbud-ptt — イヤホン（有線 EarPods）のセンターボタン長押しを push-to-talk 化し、
  # 長押し中の音声を whisper で文字起こしして前面アプリへペーストする自作ツール。
  # 本体（CGEventTap の Swift CLI）とフックスクリプトは現状 ~/Forge/earbud-ptt/ の
  # プロトタイプ（binary はローカルビルド）。ここではその実行時依存だけを宣言する。
  # プロトタイプが安定したら Swift 本体も nix derivation 化してこの部屋に引き取る。
  #
  # なぜ custom バケツか（modules/CLAUDE.md 判定）:
  #   価値の中心はイベント横取り＋ジェスチャー判定という自分の実装。ffmpeg /
  #   whisper-cpp はその部品にすぎないので core-packages ではなくこの部屋で持つ。
  #
  # whisper のモデル（ggml-large-v3-turbo.bin 等）は巨大 blob なので nix 管理せず、
  # ~/.local/share/whisper/ に手動配置する（earbud-ptt 側の README 参照）。

  home.packages = with pkgs; [
    ffmpeg # 長押し中のマイク録音（avfoundation 入力）
    whisper-cpp # whisper-cli による文字起こし
  ];

  # 常駐化。バイナリはプロトタイプ段階なのでリポジトリ外（~/Forge/earbud-ptt）を指す。
  # hidutil リマップはバイナリ自身が起動時＋60秒ごとに自己適用する。
  # 初回は本バイナリに TCC 許可（入力監視・アクセシビリティ・マイク）が要る。
  # 許可前に起動すると tap 作成に失敗して即終了するため KeepAlive は張らない。
  # 再始動: launchctl kickstart -k gui/$UID/earbud-ptt
  launchd.agents.earbud-ptt = let
    dir = "${config.home.homeDirectory}/Forge/earbud-ptt";
  in {
    enable = true;
    config = {
      Label = "earbud-ptt";
      ProgramArguments = [
        "${dir}/earbud-ptt"
        "--hold-start"
        "${dir}/whisper-hold-start.sh"
        "--hold-end"
        "${dir}/whisper-hold-end.sh"
      ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/earbud-ptt.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/earbud-ptt.log";
      EnvironmentVariables.PATH = "/etc/profiles/per-user/treo/bin:/usr/bin:/bin";
    };
  };
}
