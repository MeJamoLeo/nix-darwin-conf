{
  lib,
  pkgs,
  hermes-agent,
  ...
}: let
  # Hermes Agent（Nous Research）＝永続メモリ＋自律スキル作成を持つ自律エージェント。
  # 公式 flake は aarch64-darwin をビルド対象に含むが、**出しているモジュールは
  # nixosModules.default だけ**（outputs を実測で列挙して確認：darwinModules も
  # homeModules も存在しない）。公式 docs の getting-started/nix-setup も NixOS
  # モジュールしか扱わず darwin の記述は無い。よって darwin 側の配線は
  # このモジュールが受け持つ。
  #
  # 供給経路は packages.<system>.default を直接引く hunk と同じ作法。
  # overlays.default も存在するが供給する属性名が未確認なので、確実な方を採る
  # （overlay 経由に寄せるなら neru/herdr の作法で flake.nix の nixpkgs.overlays へ）。
  hermesPkg = hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # 自作 Hermes skill は ./skills/<name>/ に置く。ディレクトリを足せば自動で
  # ~/.hermes/skills/<name> へ symlink される（列挙不要。claude/home.nix と同パターン）。
  #
  # スコープを skill 単位にするのは意図的。~/.hermes/skills/ には **Hermes 自身が
  # 自律生成した skill** も住む（"autonomous skill creation after complex tasks" が
  # この製品の売りそのもの）。ディレクトリごと所有すると生成物を毎 rebuild で消し飛ばす。
  skillsDir = ./skills;
  skillNames =
    if builtins.pathExists skillsDir
    then
      builtins.attrNames
      (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir))
    else [];
in {
  # 本体は nix で管理する（claude-code と同じ理由）：/nix/store 配下は quarantine が
  # 付かず Gatekeeper の確認が原理的に出ない＋store は read-only なので内蔵アップデータが
  # 無効化され flake.lock でバージョン固定できる。更新は `nix flake update hermes-agent`。
  home.packages = [hermesPkg];

  # ── ~/.hermes の所有境界 ─────────────────────────────────────────────
  #
  # このディレクトリは **大半が可変状態**：config.yaml / .env / auth.json /
  # state.db / memories/ / skills/ / mcp-tokens/ / logs/ / kanban.db。
  # したがってディレクトリごと HM に所有させてはいけない。所有するのは
  # 「作者が書き、runtime が書き換えないファイル」だけに限る。
  #
  # ● config.yaml は **敢えて所有しない**。
  #   `hermes config set` / `hermes setup` / `/model` 切替が自分で書き換えるファイルで、
  #   store symlink（read-only）にすると全部壊れる。upstream の NixOS モジュールは
  #   これを「settings を recursiveUpdate で生成 ＋ .managed マーカーで CLI 側の
  #   config 変更コマンドをブロックする」managed モードで解決しているが、それを
  #   darwin に移植すると CLI と喧嘩する道具になる。~/.claude/settings.json を
  #   所有しない決定（modules/apps/herdr/home.nix 参照）と同じ判断。
  #   後から宣言的 settings を足すなら、有効なキーの正本は
  #   `nix build github:NousResearch/hermes-agent#configKeys && cat result`
  #   （Python の DEFAULT_CONFIG から抽出された全 leaf キー）。ただしこのビルド自体が
  #   429 derivation / 1.5GiB DL を要するので、本体を入れた後に叩くのが順序として安い。
  #
  # ● .env / auth.json / mcp-tokens/ も所有しない。秘密情報であり、
  #   /nix/store は world-readable なので nix に置いてはいけない
  #   （upstream docs も "Never embed secrets in Nix" と明記）。
  home.file =
    # SOUL.md ＝ エージェントの人格定義。HERMES_HOME 直下に住むと docs が明言していて、
    # runtime に書き換えられないので store symlink で所有してよい
    # （.claude/CLAUDE.md と同じ判断）。./SOUL.md を置いていなければ何もしない
    # ＝後からファイルを1枚足すだけで宣言的管理に入る。
    (lib.optionalAttrs (builtins.pathExists ./SOUL.md) {
      ".hermes/SOUL.md" = {
        source = ./SOUL.md;
        force = true; # 手動運用時代に置いた同名ファイルは上書きしてよい
      };
    })
    # NOTE: USER.md（ユーザー文脈）は docs では HERMES_HOME ではなく
    # 「working directory」に置くもので、darwin 単体運用時の実際の探索パスが
    # 未確認。確認できるまで宣言しない（誤った場所に置くと黙って無視される）。
    // builtins.listToAttrs (map (name: {
        name = ".hermes/skills/${name}";
        value.source = skillsDir + "/${name}";
      })
      skillNames);
}
