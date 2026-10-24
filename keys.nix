# keys.nix — デバイス公開鍵台帳(単一源)。
#
# 原則: 1 デバイス 1 鍵(秘密鍵は生まれたマシンから出さない)。
#   - 追加: デバイス側で `ssh-keygen -t ed25519 -C "treo@<デバイス名>"` → ここに 1 行
#   - 失効(紛失・リセット): 行を削除 or 差し替え → 各サーバーで rebuild
#   - 秘密鍵(.pub なし)は絶対にここへ入れない
#
# 消費側:
#   - mac 3台: modules/base/remote-access/darwin.nix が import して authorizedKeys に選択
#     (profile 経由で全機に入る。どの鍵を入れるかは同ファイルで名前列挙)
#   - NixOS(x1nano): modules/base/remote-access/nixos.nix が同じく import(2026-10-23 に
#     x1nano をこの flake へ移したので outputs.sshKeys 経由ではなくなった)
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
  # 実機 fingerprint KCU4DzBp... と一致確認済み(2026-10-23)。実機 .pub のコメントは
  # kif33@txstate.edu のまま(認証には無関係)。台帳側は treo@x1nano に正規化。
  x1nano = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICv3CW7sJ6BCmlrKP2znQilIz3whFw6p7EUEE9IVDCFV treo@x1nano";
}
