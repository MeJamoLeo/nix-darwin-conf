{
  config,
  pkgs,
  lib,
  ...
}: let
  home = config.home.homeDirectory;
  root = "${home}/calendar-dashboard"; # runtime working dir（mutable: out/ bin/ config）
in {
  # desktop-switcher は caldash と cp/dashboard の両方に依存する切替器。caldash 単独では
  # 意味が無く、caldash が居なければ tiny script も要らない。関心事の物理的近接を優先して
  # profile を経由せず caldash から import する（profile の未コミット diff との
  # 衝突も避けられる）。詳細: modules/custom/desktop-switcher/home.nix 冒頭。
  imports = [../desktop-switcher/home.nix];

  # カレンダー・ダッシュボード常在アプリ（本体 Google カレンダー×4面をアイコン裏に敷く自作 Swift）。
  # 本体アプリを WKWebView×4 で"最上位"ロード（iframe でないので X-Frame-Options 回避）＝
  # ダーク・Day ビュー・比率自由・4面同時、を全部満たす唯一の道。設計・経緯は
  # ./dashboard/swift/caldash-live.swift 冒頭。cp/dashboard と同型の作法（repo=正典→activation で
  # ~/ へ配置→env -i 隔離の xcrun swiftc ビルド→launchd 宣言→doctor 健診）。
  #
  # セットアップ = switch → doctor の ✗ を潰す → 初回だけ手動ログイン1回（doctor が手順表示）。

  #--- アセット配置 + Swift ビルド -------------------------------------------
  home.activation.calDashDeploy = lib.hm.dag.entryAfter ["writeBoundary"] ''
    src="${./dashboard}"
    dst="${root}"
    mkdir -p "$dst/out" "$dst/bin"

    # repo を source of truth として書き換え可能コピーを配置（out/ は runtime 状態なので温存）
    for d in swift bin; do
      rm -rf "$dst/$d"
      cp -R "$src/$d" "$dst/$d"
      chmod -R u+w "$dst/$d"
    done
    # config は ~/.config/caldash/config.json（XDG 準拠）に配置。
    # 旧 $dst/caldash-config.json が残っていれば新パスに mv（一度きり）、
    # 既に新パスに何かあれば触らない（user 変更を尊重）。
    cfg="$HOME/.config/caldash/config.json"
    mkdir -p "$(dirname "$cfg")"
    if [ ! -f "$cfg" ]; then
      if [ -f "$dst/caldash-config.json" ]; then
        mv "$dst/caldash-config.json" "$cfg"
      else
        cp -f "$src/caldash-config.json" "$cfg"
      fi
      chmod u+w "$cfg"   # nix store の read-only を継承させない（user が編集可能に）
    fi
    # 旧パスに残骸が残っていれば削除（新パスがあれば安全）
    [ -f "$cfg" ] && rm -f "$dst/caldash-config.json"

    # 機体の swiftc(CLT/Xcode) でビルド。nix の SDKROOT 汚染で stdlib を見失うため env -i 隔離。
    # CLT 不在なら switch 全体は殺さず警告のみ（cp/dashboard と同じ流儀）。
    if /usr/bin/xcrun -f swiftc >/dev/null 2>&1; then
      /usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin" \
        SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" \
        /usr/bin/xcrun swiftc -O -o "$dst/bin/caldash-live" "$dst/swift/caldash-live.swift"
    else
      echo "warning(calendar-dashboard): swiftc(CLT) 不在 — ビルドをスキップ。'xcode-select --install' 後に再 switch。" >&2
    fi
  '';

  #--- 常駐の差し替え（cp/dashboard と同じ: パス不変で bounce されないので明示 kickstart）----
  home.activation.calDashRestartLive = lib.hm.dag.entryAfter ["calDashDeploy"] ''
    label="org.nix-community.home.com.treo.calendar-dashboard-live"
    /bin/launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null || true
  '';

  #--- setupLaunchAgents の bootstrap で "I/O error 5" になるのを予防 ---------
  # home-manager の setupLaunchAgents は plain な bootstrap しか叩かないため、
  # 既存 job の load 状態が inconsistent（外部で bootout 済み等）だと失敗する。
  # 症状「I/O error 5」の主因は `launchctl unload -w` 等で agent が
  # **disabled 状態**に落ちていること（`launchctl print-disabled gui/501` で確認可）。
  # disabled のままだと bootout は No such process、bootstrap は I/O error 5 で
  # 両方詰む。ここで明示 enable してから bootout する（両方 || true で idempotent）。
  home.activation.calDashPreLaunchBootout = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    label="org.nix-community.home.com.treo.calendar-dashboard-live"
    /bin/launchctl enable "gui/$(id -u)/$label" 2>/dev/null || true
    /bin/launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  '';

  #--- セットアップ健診（腐らない手順書。初回ログイン手順も表示）------------
  home.activation.calDashDoctor = lib.hm.dag.entryAfter ["calDashRestartLive"] ''
    /bin/bash "${./dashboard/bin/doctor.sh}" "${root}" || true
  '';

  #--- launchd エージェント1本（--wallpaper で常在面を無人常駐）--------------
  launchd.agents."com.treo.calendar-dashboard-live" = {
    enable = true;
    config = {
      ProgramArguments = ["${root}/bin/caldash-live" "--wallpaper"];
      KeepAlive = true; # 落ちても復活
      RunAtLoad = true;
      StandardOutPath = "${root}/out/live.log";
      StandardErrorPath = "${root}/out/live.log";
    };
  };
}
