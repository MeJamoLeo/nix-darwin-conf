# CS 4355 — Algorithms & Analysis（Fall 2026 / sec 001 / CRN 17865 / Hantang Li）
#
# このモジュールの存在理由はひとつ：**ローカルのビルドを zyLab に一致させる**。
# シラバス原文が明示している唯一の技術的リスクがこれ：
#   "Code that works locally but fails in zyLab will not receive credit"
# 公式の採点環境は zyBook 内蔵の zyLab IDE（Linux + g++）で、ローカル IDE は
# 「開発・デバッグ用に何を使ってもよい」という位置づけ。つまりローカルの仕事は
# 「提出前に zyLab と同じ条件で通ることを確かめる」ことに尽きる。
#
# 科目の実務（zyBook / TopHat / Canvas / Gradescope / LeetCode）は全部ブラウザ側なので
# nix の担当外。TxState 共通の git identity・SSH・~/txst/ の親ディレクトリは
# modules/domain/school/txst/home.nix を参照。
#
# 言語の根拠：Fall 2026 版シラバスは言語を明記していないが、同一教員・同一 zyBook の
# Fall 2025 版に "comfortable with C++, basic data structures, recursion, and basic Big-O"
# と明記がある（HB 2504 公開シラバス。ログイン不要で
# https://api.hb2504.txst.edu/py/getsyllabus.py?class=261018905 から取得）。
#
# 学期が終わったら `git mv` で modules/_archive/ へ（cs3354 / cs3339 と同じ退役パス）。
{
  pkgs,
  lib,
  ...
}: let
  ##########################################################################
  #
  #  ⚠️ 前提（未確認）：zyLab 側の g++ バージョンと -std は実測していない。
  #
  #  ローカルは nixpkgs の GCC 15.3（既定 -std=gnu++17）で、zyBooks の runner は
  #  ふつうもっと古い。**新しい側で書いて古い側で落ちる**のが上のリスクの実体なので、
  #  下の 2 値は Week 1 の zyLab で実測して確定させること。
  #
  #    #include <cstdio>
  #    int main(){ printf("%ld %d.%d\n", __cplusplus, __GNUC__, __GNUC_MINOR__); }
  #
  #  を zyLab に投げれば1回で出る。出た値をここに反映して switch し直す。
  #
  ##########################################################################
  zyStd = "c++17"; # 暫定。zyLab の __cplusplus で確定させる
  zyWarn = "-Wall -Wextra -pedantic"; # -pedantic は「警告」止まり。zyLab の g++ も
  # GNU 拡張は通すので、ここをエラーにすると
  # ローカルだけ厳しくなって偽陽性が出る

  # zyg++ — zyLab 相当の条件で固めた g++ ラッパ。引数はそのまま素通しする。
  #
  #   zyg++ main.cpp            → g++ -std=c++17 + 警告フル。**提出可否の正本はこれ**
  #   ZYG_SAN=1 zyg++ main.cpp  → ASan/UBSan 版。境界外アクセス・UB を即座に落とす
  #
  # ⚠️ sanitizer 版だけ**コンパイラが変わる**（意図的）。nixpkgs の GCC は darwin 向けに
  #    libasan / libubsan を同梱しておらず、実測で `ld: library not found for -lasan` で
  #    落ちる。一方 Xcode CLT の /usr/bin/clang++ は ASan/UBSan がそのまま通る（実測で
  #    stack-buffer-overflow を検出）。sanitizer は**バグ発見器であって提出ゲートではない**
  #    ので、ここだけ別フロントエンドを使うのは割に合う（別コンパイラで通ることで
  #    移植性のバグも一緒に出る）。提出前の最終確認は必ず素の zyg++ で行うこと。
  #
  # このコースでいちばん効くのが ASan：配列・ヒープ・union-find を手で書く zyLab で、
  # ローカルのテストではたまたま通る境界外アクセスが、zyLab の別入力で初めて落ちる——
  # というのが "works locally, fails in zyLab" の典型的な中身。
  zygxx = pkgs.writeShellScriptBin "zyg++" ''
    set -u
    if [ "''${ZYG_SAN:-0}" != "0" ]; then
      if [ ! -x /usr/bin/clang++ ]; then
        echo "zyg++: sanitizer モードには Xcode Command Line Tools が要る (xcode-select --install)" >&2
        exit 1
      fi
      echo "zyg++: sanitizer モード → /usr/bin/clang++（GCC on darwin には libasan が無い）" >&2
      exec /usr/bin/clang++ -std=${zyStd} ${zyWarn} \
        -g -fsanitize=address,undefined -fno-omit-frame-pointer "$@"
    fi
    exec ${pkgs.gcc}/bin/g++ -std=${zyStd} ${zyWarn} "$@"
  '';

  # ex-pdf — 手書き答案のスキャンを Gradescope 提出用 PDF に束ねる（Exercises 20%）。
  # 本体は ./scripts/ex-pdf。readFile の結果は再スキャンされないので、シェルの ${...} を
  # nix にエスケープさせる必要はない。sips は macOS 標準なのでスクリプト内で絶対パス指定。
  exPdf = pkgs.writeShellScriptBin "ex-pdf" ''
    export PATH="${lib.makeBinPath [pkgs.img2pdf pkgs.coreutils pkgs.findutils]}:$PATH"
    ${builtins.readFile ./scripts/ex-pdf}
  '';

  # ~/txst/CS4355/ の骨組み。**トップ階層＝配点カテゴリ**（週割りにしない：締切が付いて
  # いるのは「zyLab 3本目」であって「第10週」ではないし、週割りだと同種の作業が16箇所に散る）。
  # 受信物（ref/）と自分の生成物を混ぜないのは CS3339 が CS3339 / CS3339_original / tmp に
  # 崩れた反省。概念ノートはここに置かず vault（3_Resources）へ——course dir に知識を溜めると
  # サイロが2つになる（CS3354 の note/ が1ファイルで死んでいる）。
  courseDirs = [
    "ref/slides" # Canvas のスライド等、教員からの受信物
    "zylabs/zylab1-inversions" # 15% / due 09-16
    "zylabs/zylab2-dp" # 15% / due 10-12
    "zylabs/zylab3-dijkstra" # 15% / due 11-04
    "zylabs/zylab4-mst" # 15% / due 11-30
    "exams/exam1" # 10-07・1枚裏表・手書き
    "exams/exam2" # 11-11・1枚裏表・手書き
    "exams/final" # 12-09 11:00-13:30・2枚裏表・手書き
    "career" # 2.5% / resume 09-21・模擬面接 11-04
    "leetcode" # ボーナス 5%
  ];

  # Exercise ×9（20%・最低1本ドロップ）。ex01 … ex09。
  exerciseDirs = map (n: "exercises/ex${lib.fixedWidthNumber 2 n}") (lib.range 1 9);
in {
  home.packages = [
    zygxx
    exPdf
    pkgs.img2pdf # ex-pdf の実体（JPEG を再エンコードせずに PDF へ埋める）

    # clangd / clang-format / clang-tidy。nixvim 側は既に lspServers.clangd.enable = true
    # なので、ここは補完・整形・静的解析の実体を PATH に置くぶん。
    # ⚠️ clangd の既定は GCC より新しい標準を仮定しがちなので、**通るかどうかの正本は
    #    clangd ではなく zyg++**。エディタが黙っていても提出前に zyg++ を通すこと。
    pkgs.clang-tools

    # 単一ファイルの zyLab には要らないが、複数ファイルに割ったときの
    # compile_commands.json 生成（= clangd がインクルードパスを解決できる状態）用。
    # シラバスが例示する CLion もこれを前提にする。
    pkgs.cmake
  ];

  # ~/txst/CS4355/ の骨組みを作る。**mkdir -p だけ**なので冪等で、switch のたびに走ってよい。
  # home.file を使って作業ファイルを nix に所有させることは**しない**——store からの
  # 読み取り専用シンボリックリンクになって手で編集できなくなるし、既存の答案を
  # 壊しうる。.gitignore だけ「無ければ置く」種扱いにして、以後は本人のもの。
  # ドキュメント（README 等）はこのディレクトリに置かない方針（本人の指定）。
  # 締切・科目メタの正史は ref/syllabus-f26.pdf と vault 側。
  # 親の ~/txst は modules/domain/school/txst/home.nix の txst-setup が作る。
  home.activation.cs4355 = lib.hm.dag.entryAfter ["txst-setup"] ''
    root="$HOME/txst/CS4355"
    mkdir -p ${lib.concatMapStringsSep " " (d: ''"$root/${d}"'') (courseDirs ++ exerciseDirs)}

    # 種ファイル：既にあれば触らない（本人の編集を尊重する）
    if [ ! -e "$root/.gitignore" ]; then
      cp ${./gitignore-template} "$root/.gitignore"
      chmod u+w "$root/.gitignore"
    fi
  '';

  # ── 意図的に入れていないもの ─────────────────────────────
  #
  # pkgs.lldb: 入れない。macOS では debugger がローカルプロセスに attach するのに
  #   署名済み debugserver が要り、nixpkgs 版はそこで詰まる。Xcode CLT 由来の
  #   /usr/bin/lldb は署名済みで既に動くので、デバッガはそちらを使う。
  #   （GCC でビルドしたバイナリも system lldb で読める。ZYG_SAN=1 の方が
  #    このコース向きの当たりは早い）
  #
  # gcc: core-packages が既に供給しているので重複させない。
}
