{
  config,
  lib,
  ...
}:
###################################################################################
#
#  Network-level content filtering.
#
#  /etc/hosts blacklist for pinpoint blocking.
#
#  /etc/hosts を書くのはこのモジュールだけ（下の WARNING）。他のモジュールが hosts で
#  止めたいドメインは、自分で hosts を触らずに `my.networkBlock.extraDomains` へ足す。
#  例：custom/youtube-gate（YouTube のページと API）。
#
###################################################################################
let
  # Domains routed to 0.0.0.0 / :: via /etc/hosts.
  blockedDomains =
    [
      "luna.amazon.com"
    ]
    ++ config.my.networkBlock.extraDomains;

  beginMark = "# >>> nix-darwin: network-block (managed) >>>";
  endMark = "# <<< nix-darwin: network-block (managed) <<<";

  # Emit both IPv4 (0.0.0.0) and IPv6 (::) entries per domain.
  # /etc/hosts entries are address-family-specific; an IPv4-only entry leaves
  # AAAA lookups to fall through to real DNS, bypassing the block.
  hostsBlock =
    "${beginMark}\n"
    + lib.concatMapStringsSep "\n" (d: "0.0.0.0 ${d}\n:: ${d}") blockedDomains
    + "\n${endMark}\n";
in {
  options.my.networkBlock.extraDomains = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "他のモジュールが /etc/hosts で止めたいドメイン（完全一致。hosts はワイルドカード不可）。";
  };

  # Marker-based /etc/hosts management.
  #
  # Why marker-based instead of full-file overwrite:
  #   - Coexists with Apple's defaults (we don't have to mirror them ourselves).
  #   - Coexists with other tools (Docker Desktop, dev tools) that legitimately
  #     write to /etc/hosts. They edit outside our markers; we only touch inside.
  #   - Aligns with nix-darwin's "share the system with macOS" philosophy.
  #
  # Why postActivation: nix-darwin's `networking` activation unconditionally
  # restores /etc/hosts.before-nix-darwin → /etc/hosts. Running after that
  # ensures our block survives.
  #
  # WARNING: this module owns /etc/hosts via postActivation.
  # If you add another module that also touches /etc/hosts, DNS resolver
  # state, or mDNSResponder, merge it INTO this module — multiple
  # postActivation defs that operate on the same network state will race
  # silently (types.lines, undefined merge order).
  # Independent operations (notifications, unrelated chmod, etc.) in other
  # modules' postActivation are fine to leave separate.
  config.system.activationScripts.postActivation.text = ''
    echo "applying /etc/hosts block (marker-based)..." >&2

    # Sweep up any sed -i.bak residue from a previously interrupted run.
    rm -f /etc/hosts.bak

    # Atomic-ish edit: drop the old managed block (only if both markers
    # are present, to avoid deleting to EOF if the file is half-corrupted),
    # then append the fresh one.
    if grep -qF '${beginMark}' /etc/hosts && grep -qF '${endMark}' /etc/hosts; then
      sed -i.bak '/${beginMark}/,/${endMark}/d' /etc/hosts
      rm -f /etc/hosts.bak
    fi

    cat >> /etc/hosts <<'HOSTS_EOF'
    ${hostsBlock}HOSTS_EOF

    chmod 644 /etc/hosts
    dscacheutil -flushcache || true
    killall -HUP mDNSResponder || true
  '';
}
