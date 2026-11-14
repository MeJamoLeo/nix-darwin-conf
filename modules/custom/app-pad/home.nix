{
  config,
  pkgs,
  ...
}: let
  ##########################################################################
  #
  #  app-pad — Option+数字 で特定のアプリを OmniWM の scratchpad として出し入れする。
  #
  #    Option+1  Linear（scratchpad 1）
  #
  #  動き（app-pad.py）：
  #    scratchpad N に入っていれば出し入れ（toggle）。窓はあるが入っていなければ
  #    フォーカスして N に登録して出す。窓が無ければ起動してから同じことをする。
  #
  #  ★ なぜ OmniWM の割当だけで済ませないのか
  #    OmniWM のキーは決まったコマンド ID しか呼べず、任意のコマンドを実行できない。
  #    toggleScratchpad.N だけだと「起動していなければ起動する」と「N への登録」ができない。
  #    なので Karabiner で受けて omniwmctl を叩く。Karabiner は Secure Input の影響も受けない
  #    （OmniWM の Option+数字 は Secure Input 中に効かない。apps/karabiner の冒頭を参照）。
  #
  #  ⚠ scratchpad から出した窓の位置は OmniWM が決める。2026-11-13 の実測では中央ではなく
  #    右寄りに出た。omniwmctl に位置を指定するコマンドは無い。AppleScript で動かすには
  #    アクセシビリティの許可が要る（未対応）。
  #
  ##########################################################################
  appPad = pkgs.writeScriptBin "app-pad" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./app-pad.py}
  '';

  # Karabiner の shell_command は PATH が最小なので、どちらも絶対パスで渡す。
  omniwmctl = "${config.home.profileDirectory}/bin/omniwmctl";

  pads = [
    {
      key = "1";
      n = "1";
      bundle = "com.linear"; # Linear
    }
  ];
in {
  home.packages = [appPad];

  programs.karabiner.rules = [
    {
      description = "Option+数字 → app-pad（アプリを OmniWM の scratchpad で出し入れ）";
      manipulators =
        map (p: {
          type = "basic";
          # optional を書かない＝ Option だけのとき。Option+Shift+1 などは OmniWM へ素通し。
          from = {
            key_code = p.key;
            modifiers.mandatory = ["option"];
          };
          to = [{shell_command = "APP_PAD_OMNIWMCTL=${omniwmctl} ${appPad}/bin/app-pad ${p.n} ${p.bundle}";}];
        })
        pads;
    }
  ];
}
