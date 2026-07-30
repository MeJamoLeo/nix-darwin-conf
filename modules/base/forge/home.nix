# forge — プロジェクト作業 repo を集約する単一親ディレクトリの規約。
#
# 旧 ~/Box の後継。「Box」は同期サービス Box.com と紛らわしく（実体はただの
# ローカルフォルダ）、訂正コストが嫌なので改名。頭文字 F はホーム直下の既存
# エントリ（A B C D G L M N P T V）と被らないので `~/F`+Tab で1文字補完できる。
#
# この module は「規約」だけを宣言する＝(1) $FORGE を張る (2) 起動時にディレクトリの
# 存在を保証する (3) 他 module が参照する単一源 `my.forgeDir` を公開する。
# 既存 repo の物理移動（mv）は home-manager の管轄外（ユーザーデータ）なので
# 一度きり手作業で行う（手順書 ~/box-to-forge-migration.md）。この module は
# その移動を "しない"。移動後の恒久的な置き場所ルールを固定するだけ。
#
# system 非依存（純粋な module 関数）なので Darwin/NixOS 双方で評価できる
# ＝flake の homeModules.forge として公開し、x1nano(NixOS) からも import する。
{
  config,
  lib,
  ...
}: let
  # ホーム直下に置く。homeDirectory はホストごと（/Users/treo・/home/treo）に
  # 解決されるのでクロス OS で正しい。
  forgeDir = "${config.home.homeDirectory}/Forge";
in {
  options.my.forgeDir = lib.mkOption {
    type = lib.types.str;
    default = forgeDir;
    description = "プロジェクト作業 repo を集約する単一親ディレクトリ（旧 ~/Box の後継）。他 module はこの値からパスを派生させる。";
  };

  config = {
    # 対話シェルで $FORGE。cp-go 等のスクリプトは実行時にこれを読める。
    home.sessionVariables.FORGE = config.my.forgeDir;

    # rebuild 時にディレクトリの存在を保証（txst-setup と同型の書き方）。
    # 空ディレクトリを作るだけ＝冪等・非破壊。移動前に先回りで掘っておける。
    home.activation.ensureForge = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p ${lib.escapeShellArg config.my.forgeDir}
    '';
  };
}
