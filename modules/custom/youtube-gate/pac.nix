{pkgs}:
# youtube-gate の遮断ルール本体。darwin.nix（システム全体）・home.nix（Zen）・librewolf.nix の共有源。
#
# 2026-10-29：YouTube に加えて X と Instagram も止める（本人の利用実態で X が SNS の最大、
# Instagram が次点。経緯は vault の SNS 対策メモ）。モジュール名は youtube-gate のまま。
#
# ⚠ ドメインを広げるときは共有ドメインを巻き込まないこと：
#   - Google 系（`.google.com` 等）を足すと検索も死ぬ。googlevideo.com を含めているのは、
#     ページを塞いでも埋め込みプレイヤーが動画ストリームだけ取りに行けてしまうため。
#   - Meta 系の共有 CDN（`fbcdn.net`・`fbsbx.com`）は足さない。WhatsApp を使っているので
#     止めると連絡が壊れる。Instagram は専用ドメイン（instagram.com・cdninstagram.com）だけ。
#
# 各ドメインは「そのもの＋全サブドメイン」を塞ぐ（dnsDomainIs のワイルドカード）。
let
  domains = [
    # YouTube
    "youtube.com"
    "youtu.be"
    "youtube-nocookie.com"
    "googlevideo.com"
    # X（旧 Twitter）。t.co は X の短縮リンク（X の外に貼られたリンクも開けなくなる。本人了承済み）
    "x.com"
    "twitter.com"
    "twimg.com"
    "t.co"
    # Instagram
    "instagram.com"
    "cdninstagram.com"
  ];
  cond = d: ''host === "${d}" || dnsDomainIs(host, ".${d}")'';
in
  pkgs.writeText "youtube-gate.pac" ''
    function FindProxyForURL(url, host) {
      host = host.toLowerCase();

      if (${builtins.concatStringsSep " ||\n        " (map cond domains)}) {
        return "PROXY 127.0.0.1:9";
      }

      return "DIRECT";
    }
  ''
