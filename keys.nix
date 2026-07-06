# keys.nix — デバイス公開鍵台帳(単一源)。
#
# 原則: 1 デバイス 1 鍵(秘密鍵は生まれたマシンから出さない)。
#   - 追加: デバイス側で `ssh-keygen -t ed25519 -C "treo@<デバイス名>"` → ここに 1 行
#   - 失効(紛失・リセット): 行を削除 or 差し替え → 各サーバーで rebuild
#   - 秘密鍵(.pub なし)は絶対にここへ入れない
#
# 消費側:
#   - ogasawara: modules/remote-access.nix が import して authorizedKeys に選択
#   - NixOS(x1nano): この flake の outputs.sshKeys 経由で参照(homeModules.tmux と同型)
#
# 純粋なデータなので darwin module にせずトップレベルに置く(どの OS からも import 可)。
{
  ogasawara = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJfPeRitnWBg6k/Nd5CLHlYvp7l42m2/Ry+lQ5FBonj9 treo@ogasawara";
  # 実機 fingerprint QBLDUDjK... と一致確認済み(2026-07-06)。
  # コメントは台帳側で treo@tanegashima に正規化済み(認証は鍵素材のみで照合される
  # ため実機 .pub のコメントと違っても無害)。実機側の修正は
  # `ssh-keygen -c -C "treo@tanegashima" -f ~/.ssh/id_ed25519` @tanegashima
  tanegashima = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGwdnP5HbekK3nbjX9R6siRhzXQdSTx/8dcHrgy7sdUT treo@tanegashima";
  # iphone-blink = "ssh-ed25519 ... treo@iphone-blink";   # Blink で生成したら追加
  # x1nano       = "ssh-ed25519 ... treo@x1nano";
}
