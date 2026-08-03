{pkgs}:
# youtube-gate の遮断ルール本体。darwin.nix（システム全体）と home.nix（Zen）の共有源。
#
# ⚠ ドメインを広げるときは Google 系を巻き込まないこと（`.google.com` を足すと検索も死ぬ）。
#   googlevideo.com を含めているのは、ページを塞いでも埋め込みプレイヤーが
#   動画ストリームだけ取りに行けてしまうため。
pkgs.writeText "youtube-gate.pac" ''
  function FindProxyForURL(url, host) {
    host = host.toLowerCase();

    if (host === "youtube.com"          || dnsDomainIs(host, ".youtube.com") ||
        host === "youtu.be"             || dnsDomainIs(host, ".youtu.be") ||
        host === "youtube-nocookie.com" || dnsDomainIs(host, ".youtube-nocookie.com") ||
        dnsDomainIs(host, ".googlevideo.com")) {
      return "PROXY 127.0.0.1:9";
    }

    return "DIRECT";
  }
''
