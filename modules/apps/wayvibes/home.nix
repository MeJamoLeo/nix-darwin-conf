# wayvibes: 打鍵音（Wayland）。soundpack は flake input のソースツリーから引く。
#
# イヤホンのときだけ鳴らす（2026-10-23）：
#   常駐させっぱなしだと音声出力を開きっぱなしにし、pipewire ごと CPU を起こし続ける
#   （x1nano 実測：4時間で wayvibes 7分46秒＋pipewire 系 約15分の CPU 時間。niri 本体は31秒）。
#   スピーカーで鳴らす必要は無いので、既定の出力先がイヤホンのときだけ wayvibes を起こす。
#   - 有線：ジャックに挿すと auto-profile（modules/base/laptop）で既定 sink が
#     `…HiFi__Headphones__sink` に切り替わる
#   - Bluetooth：既定 sink が `bluez_output.…`
#   wayvibes-auto が `pactl subscribe` で出力先の変化を待ち受け、そのたびに判定する
#   （待ち受け中はブロックしているだけなので CPU は食わない）。
#   手動でも動かせる：systemctl --user start|stop wayvibes（次に出力先が変わると上書きされる）
{
  lib,
  pkgs,
  wayvibes,
  ...
}: let
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  wayvibesAuto = pkgs.writeShellScript "wayvibes-auto" ''
    set -u
    apply() {
      sink=$(${pactl} get-default-sink 2>/dev/null || true)
      case "$sink" in
        *Headphones* | bluez_output.*) want=start ;;
        *) want=stop ;;
      esac
      if [ "$want" != "''${last:-}" ]; then
        systemctl --user "$want" wayvibes.service || true
        last=$want
      fi
    }
    last=""
    apply
    # sink / server（既定の出力先の変更）イベントのたびに判定し直す。
    ${pactl} subscribe | while read -r line; do
      case "$line" in
        *" on sink "* | *" on server "* | *" on card "*) apply ;;
      esac
    done
  '';
in {
  imports = [wayvibes.nixosModules.default]; # 名前は nixosModules だが中身は HM モジュール
  services.wayvibes = {
    enable = true; # unit は作る（wayvibes-auto と手動から start する）
    soundpack = "${wayvibes}/soundpacks/nk-cream";
    volume = 5;
  };
  # 自分では起動しない。起こすのは wayvibes-auto。
  systemd.user.services.wayvibes.Install.WantedBy = lib.mkForce [];

  systemd.user.services.wayvibes-auto = {
    Unit = {
      Description = "Run wayvibes only while the default audio output is headphones";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target" "pipewire-pulse.service"];
    };
    Service = {
      ExecStart = "${wayvibesAuto}";
      ExecStopPost = "-${pkgs.systemd}/bin/systemctl --user stop wayvibes.service";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
