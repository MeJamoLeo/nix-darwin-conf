# ノート PC としての振る舞い（x1nano）。電源・電池・蓋・指紋・キーボード・音。
{pkgs, ...}: {
  # 指紋認証（ログインと sudo）。
  services.fprintd.enable = true;
  security.pam.services.login.fprintAuth = true;
  security.pam.services.sudo.fprintAuth = true;

  # 電源プロファイルは power-profiles-daemon（DMS から切り替える）。TLP とは排他。
  services.power-profiles-daemon.enable = true;
  services.tlp.enable = false;

  # 電池の充電上限 80%（寿命のため）。起動時と復帰時に書く。
  systemd.services.battery-charge-threshold = {
    description = "Cap battery charge at 80% for longevity";
    wantedBy = ["multi-user.target"];
    after = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold'";
    };
  };
  powerManagement.resumeCommands = "echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold";

  # 蓋：バッテリーのときだけ閉じたらスリープ（持ち歩き中に電池を食わない）。
  # AC 給電中・外部ディスプレイ接続中は眠らない＝家では ssh で常に届く（2026-10-23）。
  # 以前は常に ignore で、sleep/suspend target ごと無効にしていた。
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    IdleAction = "ignore";
  };
  # hibernate はスワップへの書き出しが要る＆未検証なので無効のまま。suspend だけ使う。
  systemd.targets = {
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };
  networking.networkmanager.wifi.powersave = false;

  # CapsLock ⇄ 左 Ctrl をスキャンコードで入れ替える（内蔵キーボードと USB/Bluetooth）。
  # xkb ではなく hwdb なので TTY・Wayland・X のどこでも同じに効く。
  services.udev.extraHwdb = ''
    evdev:atkbd:dmi:*
     KEYBOARD_KEY_3a=leftctrl
     KEYBOARD_KEY_1d=capslock

    evdev:input:b0003*
    evdev:input:b0005*
     KEYBOARD_KEY_70039=leftctrl
     KEYBOARD_KEY_700e0=capslock
  '';

  # 音：pipewire。カード挿抜でプロファイル/ポートを自動で切り替える。
  services.pipewire.wireplumber.extraConfig."51-alsa-autoswitch" = {
    "monitor.alsa.rules" = [
      {
        matches = [{"device.name" = "~alsa_card.*";}];
        actions.update-props = {
          "api.acp.auto-profile" = true;
          "api.acp.auto-port" = true;
        };
      }
    ];
  };

  environment.systemPackages = with pkgs; [brightnessctl pulseaudio];
}
