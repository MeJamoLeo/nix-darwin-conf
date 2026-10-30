{lib, ...}: let
  ##########################################################################
  #
  #  earbud-ptt — 有線 EarPods のリモコンで Handy の文字起こしを操作する。
  #
  #    センター長押し（0.5s）  → 録音開始（開始音）。**離してから話す**
  #    録音中にセンター短押し  → 停止・文字起こし・前面アプリへ貼付
  #    通常時のセンター短押し  → 再生／一時停止（素通し）
  #    音量+ 2連打（500ms）    → Enter（送信）
  #    音量- 2連打             → Cmd+Z（取り消し）／録音中なら Esc（録音キャンセル）
  #    音量± 1回               → 音量（500ms 遅れて出る）
  #
  #  このモジュールは apps/karabiner と apps/handy の**オプション経由でだけ**配線する。
  #  profiles/mac-workstation.nix の import を外せば規則は消え、Handy は
  #  push-to-talk（apps/handy の mkDefault）に戻る。
  #
  #  ★ 自作 Swift CLI（~/Forge/earbud-ptt）からの移行（2026-10-29）
  #    旧版は launchd 起動で一度も動かなかった。リポジトリ直下に Info.plist と
  #    _CodeSignature をコミットしていたせいで macOS がリポジトリ自体を bundle と
  #    みなし、.git を含む封印が commit のたびに壊れて TCC が本人確認できなかった
  #    （tccd: kTCCServicePostEvent authValue=0）。Karabiner（Developer ID 署名済み・
  #    許可済み）と Handy に乗り換えて自作の常駐プロセスを無くした。
  #    旧リポジトリは GitHub（MeJamoLeo/earbud-ptt）で archive 済み・ローカルは削除済み。
  #
  #  ★ なぜ「押しながら話す」ではなくトグルなのか（実測）
  #    EarPods のリモコンは押下中マイク線を短絡する。押した瞬間に入力が -73dB
  #    （デジタル無音）になり、Handy は 0 サンプルだった。EarPods 自身のマイクでは
  #    押しながら話すことが物理的にできない（iPhone の Siri が「離してから話す」なのと同じ）。
  #
  #  ★ デバイスの実測（karabiner_cli --list-connected-devices / EventViewer, 16.3.0）
  #    "Headset"（Transport=Audio）、identifiers は is_consumer のみで vendor=product=0。
  #    ボタンは play_or_pause / volume_increment / volume_decrement。
  #    センターは down/up が別々に来る（長押し可）。音量± は down/up 同時刻のパルス
  #    （長押し不可 → 連打回数で分岐）。Karabiner が grab すると長押しの Siri 起動も止まる。
  #
  #  ⚠ 録音中フラグ（earpods_recording）は Karabiner 側の推測状態。Handy 側で
  #    キーボードの Esc などで止めるとズレ、次の短押しが1回だけ「録音開始」になる。
  #    もう一度短押しすれば戻る。
  #
  ##########################################################################
  headset = {
    is_consumer = true;
    vendor_id = 0;
    product_id = 0;
  };
  # 他キーボードのメディアキーを巻き込まないよう、全規則を EarPods に縛る。
  onHeadset = [
    {
      type = "device_if";
      identifiers = [headset];
    }
  ];

  recVar = "earpods_recording";
  setVar = name: value: {set_variable = {inherit name value;};};
  varIs = name: value: {
    type = "variable_if";
    inherit name value;
  };

  # 念のためリピートを止める（音量± は down/up が同時刻のパルス）。
  # ※ 2026-10-29 に「z が出続けた」のは押しっぱなしではなく、Orca のターミナルが
  #   Cmd+Z を kitty キーボード形式（ESC[122;9u）で Claude Code に渡し、Claude Code が
  #   未割り当ての super+z を `z` として打ち込んでいたため。直したのは受け側：
  #   ~/.claude/keybindings.json の Chat に `"cmd+z": "chat:undo"`（Orca が書くファイルなので
  #   nix 管理にしていない）。Orca 側の同類の不具合は stablyai/orca#25926。
  norepeat = ev: ev // {repeat = false;};

  # 2連打の定番パターン：1回目は変数を立てて 500ms 待ち、来なければ元のキーを出す。
  # 300ms だと2回目が間に合わないことがあった（2026-10-29 実測）ので 500ms。
  # recAction を渡すと、録音中の2連打だけ別アクションにする。
  doubleTap = {
    from,
    var,
    action,
    recAction ? null,
  }:
    lib.optional (recAction != null) {
      type = "basic";
      from.consumer_key_code = from;
      conditions = onHeadset ++ [(varIs var 1) (varIs recVar 1)];
      to = [(setVar var 0) (setVar recVar 0)] ++ map norepeat recAction;
    }
    ++ [
      {
        type = "basic";
        from.consumer_key_code = from;
        conditions = onHeadset ++ [(varIs var 1)];
        to = [(setVar var 0)] ++ map norepeat action;
      }
      {
        type = "basic";
        from.consumer_key_code = from;
        conditions = onHeadset;
        to = [(setVar var 1)];
        to_delayed_action = {
          to_if_invoked = [(setVar var 0) {consumer_key_code = from;}];
          to_if_canceled = [(setVar var 0)];
        };
        parameters."basic.to_delayed_action_delay_milliseconds" = 500;
      }
    ];
in {
  programs.karabiner.devices = [
    {
      identifiers = headset;
      ignore = false;
    }
  ];

  programs.karabiner.rules = [
    {
      description = "EarPods: センター長押し=録音開始（離してから話す）／録音中の短押し=停止・貼付／それ以外の短押し=再生停止";
      # 上から先に一致したものが使われる。録音中の分岐を先に置く。
      manipulators = [
        {
          type = "basic";
          from.consumer_key_code = "play_or_pause";
          conditions = onHeadset ++ [(varIs recVar 1)];
          to = [(setVar recVar 0) {key_code = "f18";}];
        }
        {
          type = "basic";
          from.consumer_key_code = "play_or_pause";
          conditions = onHeadset;
          # F18 は Handy の transcribe（fn+f18。apps/handy 参照）。
          to_if_held_down = [(setVar recVar 1) {key_code = "f18";}];
          to_if_alone = [{consumer_key_code = "play_or_pause";}];
          parameters = {
            "basic.to_if_held_down_threshold_milliseconds" = 500;
            "basic.to_if_alone_timeout_milliseconds" = 500;
          };
        }
      ];
    }
    {
      description = "EarPods: 音量+ 2連打=Enter（送信）";
      manipulators = doubleTap {
        from = "volume_increment";
        var = "earpods_vol_up";
        action = [{key_code = "return_or_enter";}];
      };
    }
    {
      description = "EarPods: 音量- 2連打=Cmd+Z（取り消し）／録音中は Esc（録音キャンセル）";
      manipulators = doubleTap {
        from = "volume_decrement";
        var = "earpods_vol_down";
        action = [
          {
            key_code = "z";
            modifiers = ["left_command"];
          }
        ];
        recAction = [{key_code = "escape";}];
      };
    }
  ];

  programs.handy.settings = {
    # トグル方式（押すたびに開始/停止）。理由は冒頭の「なぜトグルなのか」。
    push_to_talk = false;
    # 離してから話すので、録音開始の合図音が要る。
    audio_feedback = true;
    # null ＝ OS 既定の入力（EarPods 挿入時は "External Microphone"）。
    # 連係の "iPhone SE Microphone" が選ばれていて 0 サンプルになっていた（2026-10-29）。
    selected_microphone = null;
  };
}
