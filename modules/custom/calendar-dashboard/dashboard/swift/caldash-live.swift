// caldash-live — カレンダー・ダッシュボード（本体 Google カレンダー×4面）
// 本体アプリを WKWebView で"最上位"ロード（iframe でないので X-Frame-Options 回避）。
// 全面が .default() データストア共有 → ログイン1回で全面認証・再起動で永続（実測済み）。
//
// レイアウト（4面）: 3 等幅カラム、右カラムだけ上下スタック（2026-10-02 ユーザー決定）。
//   ┌────────┬────────┬────────┐
//   │ 4週     │ 今週    │ 来週    │   ← 来週は縮小 zoom（nextWeekZoomScale）。上段 rightTopRatio
//   │ (全高)  │ (全高)  ├────────┤
//   │         │         │ todo    │   ← 今日の todo md を leaf で描画（Google カレンダーではなくローカル面）
//   └────────┴────────┴────────┘
// WHY 右だけ分割: 4週ビューが既に「来週」を含むので、来週ペインは全高の大きさが要らない
//      （縮小 zoom で十分）。空いた右下を todo に回すと、旧「左下の月ペイン半分」より広く取れる。
// WHY 3 カラム等幅: ユーザー要望「幅は全て同じように」。leftColumnRatio=1/3 で左を固定し、
//      残りを今週・来週で等分（中央だけ hour gutter 分 +extra＝日列幅を来週と揃える不変条件は維持）。
// WHY 来週の zoom を縮める: 高さが半分になるので、同じ zoom だと 0-24h がスクロール無しで収まらない。
//      週 zoom × nextWeekZoomScale（既定 0.75）。解像度スケール式は週 zoom 側に先に掛かるので、
//      画面ごとの補正の上に乗る（式 → 来週だけ倍率）。
// 左上は月ビューでなく Google カレンダーのカスタムビュー（4週・月曜始まり・本体設定済み）。
// WHY: 月ビューは月末で打ち切られ、翌月に入った週が見えなくなる。4週カスタムビューは
//      常に「今週」始まりなので、直近4週間が月境界に関係なく連続して見える（2026-10-02 ユーザー要望）。
//
// 右下は todo パネル: ~/Store/30_Work/todo/YYYY/YYYYMMDD-todo.md（当日）を
//   `leaf --inline ansi:<cols> <file>` で描画し、ANSI(SGR) を HTML に変換して WKWebView に出す。
// WHY leaf: ユーザーが todo の閲覧に `leaf -w` を選んだ。その描画（☐/☑・区切り線・配色）をそのまま使う。
// WHY ターミナル窓にしない: 他社製ターミナルの窓は壁紙レイヤー（アイコンの裏）に置けない。
//      caldash の窓は desktopWindow レベルなので、面として caldash の中に居る必要がある。
// WHY --inline で描画: leaf 自前の描画を保ったまま caldash 内に収まる（ターミナルエミュ不要）。
//      -w（常駐監視）は使わず、こちらでファイル変更を見て再実行する（leaf -w 相当）。
// WHY 2 秒 mtime ポーリング: ファイル+ディレクトリの FS イベント監視は atomic rename 書き込みで
//      fd が旧 inode を指して切れる・日付跨ぎでパスが変わる、の再接続処理が要る。ポーリングは
//      パス・mtime・桁数・zoom の組を比べるだけで、これら全部（更新/rename/日付変更/リサイズ/
//      今日のファイル出現）を同じ1箇所で拾える。stat 1回/2秒は無視できるコスト。
// 当日ファイルが無い間（roll ジョブが 06:00 に作る＝00:01〜06:00）は、最新の過去ファイルを
//   「showing M/D (today's file not created yet)」の注記付きで出す（空白にしない）。
// leaf が使えない（バイナリ無し/非0終了）ときは、leaf 風の素朴な等幅 HTML に自前で描く
//   （見出し太字・`- [ ]`→☐・`- [x]`→☑ 淡緑・字下げ保持）。エラー文は出さない（leaf 無しは正常系の1つ）。
//   エラーを出すのは「ファイルが読めない」ときだけ。
// WHY 自前フォールバック: leaf は nixpkgs に無く（手動で ~/.local/bin/leaf に置く、config: leafPath）、
//   持ち出し機（tanegashima）には入っていないことがある。入れ忘れで todo 面が死ぬのは割に合わない。
//
// 環境変数（起動時に1回読む。launchd の EnvironmentVariables で機体ごとに差し込む）:
//   CALDASH_TODO_DIR        todo ファイルのルート。既定 ~/Store/30_Work/todo。
//                           tanegashima は ogasawara の読み取り専用ミラー ~/.cache/todo-mirror を指す
//                           （modules/custom/todo-board/remote.nix の todo-mirror が 5 分ごとに更新）。
//   CALDASH_TODO_STALE_MIN  <dir>/.synced の mtime がこの分数より古い（or 無い）と、todo 面の先頭に
//                           `last sync HH:MM (ogasawara unreachable?)` を淡色で出す。既定 0=無効
//                           （ogasawara は ~/Store を直読みで、同期の概念が無いため）。
//
// モード: （無フラグ）interactive=通常窓・ログイン用 / --wallpaper=常在面（アイコン裏・透過・全Space・無人）
// 設定: ~/calendar-dashboard/caldash-config.json（env CALDASH_CONFIG で上書き）。
//       gap / zoom / weekZoom / baseZoom / baseWeekZoom / referenceWidth /
//       leftColumnRatio（左カラム幅比。等幅なら 0.3333）/ rightTopRatio（右カラム上段=来週の高さ比。既定 0.5）/
//       nextWeekZoomScale（来週ペインだけ週 zoom に掛ける倍率。既定 0.75）/
//       todoZoomScale（todo ペインだけ月 zoom に掛ける倍率。既定 1.3333）/
//       account(u/N) / tz / backgroundOpacity /
//       leafPath（leaf バイナリ。既定 ~/.local/bin/leaf）。
// 日次: ローカル 00:01 に再ロード（各面を今日基準に再アンカー＋来週 URL 再計算・todo 面は当日ファイルへ切替。
//       4週ビューは本体側が「今週始まり」で描くので再ロードだけで当週に追随する）。
//       ※イベントデータ自体は本体 SPA が自前同期するので定期リロードはしない。
//
// 週ペインの時間グリッド高さ伸縮（2026-10-02 追加。pageZoom は固定のまま）:
//   今週[2]・来週[3]の 0-24h グリッドを「ペインの利用可能高さ」にちょうど収まるよう、
//   1 時間行の高さだけを伸縮する（ページ内 JS = WEEK_STRETCH_JS。zoom=baseWeekZoom×解像度式×nextWeekZoomScale は不変）。
//   WHY: 固定 zoom だとペイン高と 24h グリッド高が画面ごとに噛み合わず、グリッドが 3/4 で終わって下が
//        空白になった（ユーザー指摘）。最初は pageZoom で高さを合わせたが、zoom を変えると文字が大きくなり
//        情報密度が下がる（ユーザー指摘）。文字サイズ＝zoom は固定し、時間行の高さ（px/時）だけを動かす。
//        文字を縦に歪ませない（scaleY 等の transform は使わない）。来週ペイン（高さ半分）は k<1 で圧縮され、
//        短い予定は文字が切れるが許容。
//   DOM 実測（2026-10-02・class 名はハッシュなので log 用途のみ）: 時間行 = 24 個の等高 div（1 個 48px）で
//        罫線は ::after。時刻ラベル gutter も 24 個の 48px セル。イベント/現在時刻線は inline の `top: Npx; height: Npx`
//        絶対配置（% ではない）。→ 時間行の高さは CSS で上書き、イベント/現在時刻線の top/height は
//        JS が k 倍に書き換える（元値は data 属性に保存＝冪等。GCal の再描画で値が変われば新値を元値として採り直す）。
//   選択は landmark / 構造（role=main 内の overflow-y スクローラ・role=row・24 個の等高子）だけ。ハッシュ class は使わない。
//   JS は MutationObserver + 1.5 秒周期 + resize で追随。差が 4 device px 以下なら動かさない（flapping 防止）。
//   Swift 側は 2 秒周期で状態を読み、変化時だけ log: `[caldash] stretch week pane=.. screen=WxH k=.. natural=.. avail=..`。
// 終了 = プロセス kill のみ。システム状態は何も変えない。
//
// セキュリティ（監査 2026-07-27 反映）:
//   - isInspectable / JS 自動 window.open は無人常駐(--wallpaper)では無効（認証 view への侵入面を絞る）。
//   - createWebViewWith / decidePolicy は wallpaper 時 Google 一族ホストのみ許可（認証 view の外部誘導阻止）。
//   - .default() に本人の常時 Google セッション cookie が永続する点は自覚の上で受容（ブラウザ同等リスク）。

import Cocoa
import WebKit

let SAFARI_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
let WALLPAPER = CommandLine.arguments.contains("--wallpaper")

// wallpaper mode 専用: Google カレンダー本体のクロム（トップバー・サイドバー）を消して
// 盤面だけ残す。class 名は毎リリースでハッシュ化される（例: .aRlgFf）ため landmark で当てる。
// トップバー(=role='banner')は display:none で真に消す。左サイドバー（Create/ミニカレ/
// カレンダー一覧/フッター）は Google が非-landmark で組んでいる可能性が高いため、
// role='main' を viewport 全面に position:fixed で被せる「構造非依存」戦略で覆い隠す。
// これで DOM を残したまま視覚的にサイドバーが消え、Google の class ハッシュ変更にも
// 巻き込まれない。interactive mode ではログイン・ナビ用に UI を温存する。
// クロム消し専用。透過は NSWindow.alphaValue で window 全体に一律適用するので、
// ここで CSS 側の背景を触る必要は無い（触ると event card や時刻軸が二重に透過して
// 変な見え方になる）。html/body の overflow だけ抑えてスクロール暴発を防ぐ。
// today ハイライト: GCal は today 要素に `.F262Ye` class を付けるので、週/月ビューの
// columnheader（曜日ヘッダ）と gridcell（events grid の today 列）に薄い青背景。
// 内側の要素にも .F262Ye は伝播するが role で絞ることで stacking の重色を防ぐ。
let HIDE_CHROME_CSS = """
[role='banner'] { display: none !important; }
[role='main'] {
  position: fixed !important;
  inset: 0 !important;
  width: 100vw !important;
  height: 100vh !important;
  z-index: 999999 !important;
}
html, body { overflow: hidden !important; margin: 0 !important; padding: 0 !important; }
[role='columnheader'].F262Ye,
[role='gridcell'].F262Ye {
  background-color: rgba(66, 133, 244, 0.15) !important;
}
"""

// 週ペイン限定: イベントブロックの文字だけ縮小して1イベントあたりの情報量を上げる
// （pane zoom と違いグリッドの高さは変えないので、週ペインの下に黒帯が出ない）。
// data-eventid はイベント要素の安定属性。実効サイズは週ペインの pageZoom が掛かるので、
// config の weekZoom（式モードなら baseWeekZoom）に応じて見え方が変わる。
// 月ペインには当てない: 月ビューのチップは GCal の JS がフォント計測込みで絶対配置する
// ため、CSS でフォントだけ縮めると複数日バーと通常チップの文字が重なる（2026-08-07
// スクショ実測）。
//
// ⚠ チップ要素そのものの font-size は絶対に触らない（2026-08-10 DOM probe で確定）。
// 週ビューも「時間ベース配置だから安全」ではない。安全なのは時間帯チップだけで、
// 上端の**終日行**は月ビューと同じ相対配置：
//   終日チップ  inline style = `left: 0%; width: 14.29%; top: 0em / 1em / 2em …`
//   時間帯チップ inline style = `top: 287px; height: 46px; …`（px 絶対＝font 非依存）
// 終日側の `top: Nem` は **チップ自身の font-size を 1 行の高さとして使う** 設計で、
// 素の状態は 1em = 24px = チップ高 24px＝隙間なくぴったり積み上がる（probe 実測）。
// ここで `[data-eventid] { font-size:10px }` を当てると stride だけ 10px に潰れ、
// チップ高は padding 由来で 24px 残るため、終日が 2 件以上ある日は 1 件につき 14px
// ずつ重なって読めなくなる（2026-08-10 に MON 3 件で顕在化）。
// 対策: 本体は触らず**子孫を全部**縮める。span 限定では足りない（丈の高いチップは
// タイトル/時刻/場所を div で多行レンダリングするため 2026-08-10 の第1版が取り逃し、
// Bobcat Bounty 等だけ文字が 1.7 倍のまま残った＝スクショ実測）。GCal は子要素に
// 明示 font-size を置くので、本体に当てた継承頼みでも子孫直指しでも結果は同じ。
// 時間帯チップ側は本体にも当て直す（px 絶対配置なので font-size 非依存＝安全。
// 直接テキストノードを持つ場合の取り逃しを塞ぐ。`.mDPmMe` = 時間帯 events grid）。
let WEEK_EVENT_FONT_CSS = """
[data-eventid] * {
  font-size: 10px !important;
  line-height: 1.2 !important;
}
.mDPmMe [data-eventid] {
  font-size: 10px !important;
  line-height: 1.2 !important;
}
"""

// 週ペイン用: 0-24h グリッドの 1 時間行の高さを伸縮して、スクローラの高さにちょうど合わせるページ内 JS。
// pageZoom は触らない（文字サイズ不変）。詳細・WHY はファイル冒頭「週ペインの時間グリッド高さ伸縮」。
// window.__caldashZoom は Swift が 2 秒毎に書く pageZoom（deadband を device px で評価するため）。
// window.__caldashStretch = {k, hour, h0, natural, avail, row, cells, events} を Swift が読んで log する。
let WEEK_STRETCH_JS = """
(() => {
  if (window.__caldashStretchInstalled) return;
  window.__caldashStretchInstalled = true;
  const STYLE_ID = 'caldash-stretch-style';
  const MARK = 'data-caldash-hour';                       // 時間セルの印（CSS が height を当てる）
  const OT = 'data-caldash-ot', OH = 'data-caldash-oh';   // 元の top / height（px 数値）
  const ST = 'data-caldash-st', SH = 'data-caldash-sh';   // 自分が最後に書いた top / height 文字列
  const DEADBAND_DEV_PX = 4, K_MIN = 0.3, K_MAX = 4;
  const st = { k: 1, hour: 0, h0: 0, natural: 0, avail: 0, row: 0, cells: 0, events: 0, applied: false };
  window.__caldashStretch = st;
  const rectH = el => el.getBoundingClientRect().height;

  // 時間グリッドのスクローラ = role=main 内で overflow-y が scroll|auto、role=row>gridcell を含む最大の要素。
  const findScroller = () => {
    const root = document.querySelector("[role='main']");
    if (!root) return null;
    let best = null, bh = 0;
    root.querySelectorAll('div').forEach(el => {
      const cs = getComputedStyle(el);
      if (cs.overflowY !== 'scroll' && cs.overflowY !== 'auto') return;
      const h = rectH(el);
      if (h < 150 || h <= bh) return;
      if (!el.querySelector("[role='row'] [role='gridcell']")) return;
      best = el; bh = h;
    });
    return best;
  };

  // 時間セル群 = 子が 23〜26 個の親のうち、先頭の子（>=20px）と同じ高さの子がちょうど 23〜25 個あるもの。
  // （gutter 列は末尾にタイムゾーン一覧用の別高さの子が 1 個付くので「全員等高」ではなく「等高が 23〜25 個」で見る）
  // スクローラ内（罫線行）と、スクローラの兄弟（時刻ラベル gutter）の両方から探す。
  const findHourGroups = (sc) => {
    const groups = [];
    const scan = base => base.querySelectorAll('div').forEach(par => {
      const n = par.children.length;
      if (n < 23 || n > 26 || par.closest('[data-eventid]')) return;
      const hs = [...par.children].map(rectH);
      const h = hs[0];
      if (!(h >= 20)) return;
      const same = [...par.children].filter((c, i) => Math.abs(hs[i] - h) < 0.6);
      if (same.length >= 23 && same.length <= 25) groups.push(same);
    });
    scan(sc);
    for (const sib of sc.parentElement.children) if (sib !== sc) scan(sib);
    return groups;
  };

  const ensureStyle = h => {
    let s = document.getElementById(STYLE_ID);
    if (!s) { s = document.createElement('style'); s.id = STYLE_ID; (document.head || document.documentElement).appendChild(s); }
    const txt = `[${MARK}] { height: ${h}px !important; min-height: 0 !important; max-height: none !important; }`;
    if (s.textContent !== txt) s.textContent = txt;
  };

  const num = v => { const x = parseFloat(v); return isFinite(x) ? x : null; };
  // イベント/現在時刻線: スクローラ内で inline に px の top を持つ絶対配置要素。top/height を k 倍。
  const rescaleAbs = (sc, k) => {
    let n = 0;
    sc.querySelectorAll("[style*='top']").forEach(el => {
      const t = el.style.top;
      if (!t || !t.endsWith('px') || getComputedStyle(el).position !== 'absolute') return;
      // top: GCal が書き換えていれば（現在値 ≠ 自分が書いた値）新しい値を元値として採り直す。
      if (el.getAttribute(ST) !== t) el.setAttribute(OT, String(num(t)));
      const ot = num(el.getAttribute(OT));
      const nt = (ot * k).toFixed(2) + 'px';
      if (el.style.top !== nt) el.style.top = nt;
      el.setAttribute(ST, el.style.top);
      const hh = el.style.height;
      if (hh && hh.endsWith('px')) {
        if (el.getAttribute(SH) !== hh) el.setAttribute(OH, String(num(hh)));
        const oh = num(el.getAttribute(OH));
        const nh = (oh * k).toFixed(2) + 'px';
        if (el.style.height !== nh) el.style.height = nh;
        el.setAttribute(SH, el.style.height);
      }
      n++;
    });
    return n;
  };

  let running = false;
  const pass = () => {
    if (running) return;
    running = true;
    try {
      const sc = findScroller();
      if (!sc) return;
      const row = sc.querySelector("[role='row']");
      const A = rectH(sc), R = rectH(row);
      const groups = findHourGroups(sc);
      if (!groups.length) return;
      // 印の無い（＝新規/再描画で素の）セル群があれば、その高さが自然な 1 時間高 h0。
      let fresh = false;
      groups.forEach(g => { if (!g[0].hasAttribute(MARK)) { fresh = true; st.h0 = rectH(g[0]); } });
      if (st.h0 <= 0) return;
      const cur = rectH(groups[0][0]);           // 現在の 1 時間行の実高さ
      const cnt = groups[0].length;
      const extra = R - cnt * cur;               // グリッド行のうち時間行以外（罫線 1px 等）
      const natural = extra + cnt * st.h0;
      const zoom = window.__caldashZoom || 1;
      const deadband = DEADBAND_DEV_PX / zoom;   // device px → CSS px
      st.avail = A; st.natural = natural; st.row = R; st.cells = cnt;
      if (fresh || !st.applied || Math.abs(R - A) > deadband) {
        let hour = (A - extra) / cnt;
        const k = Math.max(K_MIN, Math.min(K_MAX, hour / st.h0));
        hour = k * st.h0;
        // 目標が現状と deadband 内に収まる（＝すでに合っている）なら hour を据え置いて flapping を防ぐ。
        if (!st.applied || fresh || Math.abs(hour - st.hour) * cnt > deadband) { st.hour = hour; st.k = k; }
      }
      ensureStyle(st.hour);
      groups.forEach(g => g.forEach(c => { if (!c.hasAttribute(MARK)) c.setAttribute(MARK, '1'); }));
      st.events = rescaleAbs(sc, st.k);
      st.applied = true;
    } catch (e) { st.err = String(e); }
    finally { running = false; }
  };

  let timer = 0;
  const schedule = () => { if (timer) return; timer = setTimeout(() => { timer = 0; pass(); }, 60); };
  const start = () => {
    const root = document.querySelector("[role='main']");
    if (!root) { setTimeout(start, 500); return; }
    new MutationObserver(schedule).observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['style'] });
    window.addEventListener('resize', schedule);
    setInterval(pass, 1500);
    pass();
  };
  start();
})();
"""

// ---- 設定（既定値。config で上書き）----
var ACCOUNT = 0
var TZ_ID   = "America/Chicago"
var GAP: CGFloat = 6
var MONTH_ZOOM: CGFloat = 0.75       // 月ペイン pageZoom（<1 で文字を小さく＝密度↑）
var WEEK_ZOOM: CGFloat = 0.5         // 週ペイン pageZoom（1日 0-24 時をスクロール無しで収める用）
// GCal 週ビューの hour gutter CSS 幅（.lqYlwe が JS で固定する 96px、実測）。
// 中央 pane (今週) はこれを内部で消費するので、幅を +GCAL_WEEK_GUTTER_PX*weekZoom
// 余分にとって右 pane (来週=gutter 消去済) の 1 日列幅と揃える。
let GCAL_WEEK_GUTTER_PX: CGFloat = 96
// 解像度スケール式（referenceWidth が config にあると式モード起動＝main モニタ幅で自動追随）。
// 例: baseMonthZoom=0.9 referenceWidth=2560 → 2560幅で 0.9・3840幅で ~0.735・5120幅で ~0.636（sqrt ダンパー）。
// 現画面幅の変化（モニタ挿抜・SetResolution）は didChangeScreenParametersNotification で購読して再計算。
var BASE_MONTH_ZOOM: CGFloat? = nil
var BASE_WEEK_ZOOM: CGFloat? = nil
var REFERENCE_WIDTH: CGFloat? = nil
// 左カラム（4週・全高）が usable 幅に占める比率（config: leftColumnRatio）。
// nil = 旧来の 3 等幅（左 = (usable - extra)/3）。値を入れると左を痩せさせた分だけ
// 週ペイン 2 枚が広がる＝1 日あたりの列幅が増える。月ビューは 7 列さえ保てば
// 潰れないので、情報量の主戦場である週側に幅を寄せるための調整弁。
// 2026-09-17: 0.25 で運用開始（2560 幅で 左 637px / 週 917px・994px）。
var LEFT_COLUMN_RATIO: CGFloat? = nil
// 右カラム（来週 / todo の縦スタック）の上段=来週が占める高さ比（config: rightTopRatio）。
var RIGHT_TOP_RATIO: CGFloat = 0.5
// 来週ペインだけに掛ける zoom 倍率（config: nextWeekZoomScale）。式適用後の週 zoom に乗る。
var NEXT_WEEK_ZOOM_SCALE: CGFloat = 0.75
// todo ペインだけに掛ける zoom 倍率（config: todoZoomScale）。月 zoom に乗る。
// 既定 1.3333＝本人指定で todo を月 zoom 0.75 から zoom 1.0 相当に（2026-10-02）。
var TODO_ZOOM_SCALE: CGFloat = 1.3333
// 背景 alpha（config: backgroundOpacity）。1.0=完全不透明、<1.0 で壁紙が透ける。
// window.isOpaque + backgroundColor + GridView.layer + WKWebView.drawsBackground +
// CSS 注入の全レイヤーに一貫適用する（どこか一箇所でも opaque だと透過は死ぬ）。
var BG_OPACITY: CGFloat = 1.0
// leaf バイナリのパス（config: leafPath）。nixpkgs に無いので手動配置の ~/.local/bin/leaf が既定。
var LEAF_PATH = "~/.local/bin/leaf"
// todo ファイルのルート。YYYY/YYYYMMDD-todo.md が下に並ぶ。
// env CALDASH_TODO_DIR で上書き（ミラーを読む機体用）。
let TODO_DIR: String = {
    let v = ProcessInfo.processInfo.environment["CALDASH_TODO_DIR"] ?? ""
    return v.isEmpty ? "~/Store/30_Work/todo" : v
}()
// 鮮度警告のしきい値（分）。0=無効。
let TODO_STALE_MIN: Int = Int(ProcessInfo.processInfo.environment["CALDASH_TODO_STALE_MIN"] ?? "") ?? 0

struct Config: Codable {
    var gap: Double?; var monthZoom: Double?; var weekZoom: Double?
    var baseMonthZoom: Double?; var baseWeekZoom: Double?; var referenceWidth: Double?
    var leftColumnRatio: Double?; var rightTopRatio: Double?; var nextWeekZoomScale: Double?; var todoZoomScale: Double?
    var account: Int?; var tz: String?
    var backgroundOpacity: Double?
    var leafPath: String?
}
// 設定ファイル: 既定 ~/.config/caldash/config.json (XDG_CONFIG_HOME 準拠、
// 環境変数 XDG_CONFIG_HOME が空でなければそちらを尊重)。CALDASH_CONFIG 環境変数で
// 個別 override 可能。旧 ~/calendar-dashboard/caldash-config.json は home-manager
// activation が起動前に新パスへ mv 済み。
func defaultConfigPath() -> String {
    let env = ProcessInfo.processInfo.environment
    let xdg = (env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 })
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
    return "\(xdg)/caldash/config.json"
}
func loadConfig() {
    let path = ProcessInfo.processInfo.environment["CALDASH_CONFIG"] ?? defaultConfigPath()
    print("[caldash] config file: \(path)")
    guard let data = FileManager.default.contents(atPath: path),
          let c = try? JSONDecoder().decode(Config.self, from: data) else { return }
    if let v = c.gap { GAP = CGFloat(v) }
    if let v = c.monthZoom { MONTH_ZOOM = CGFloat(v) }
    if let v = c.weekZoom { WEEK_ZOOM = CGFloat(v) }
    if let v = c.baseMonthZoom { BASE_MONTH_ZOOM = CGFloat(v) }
    if let v = c.baseWeekZoom { BASE_WEEK_ZOOM = CGFloat(v) }
    if let v = c.referenceWidth { REFERENCE_WIDTH = CGFloat(v) }
    // 0 や 1 を入れるとカラムが消える／週が潰れるので実用域に丸める。
    if let v = c.leftColumnRatio { LEFT_COLUMN_RATIO = max(0.1, min(0.6, CGFloat(v))) }
    if let v = c.rightTopRatio { RIGHT_TOP_RATIO = max(0.2, min(0.8, CGFloat(v))) }
    if let v = c.nextWeekZoomScale { NEXT_WEEK_ZOOM_SCALE = max(0.2, min(1.5, CGFloat(v))) }
    if let v = c.todoZoomScale { TODO_ZOOM_SCALE = max(0.5, min(2.5, CGFloat(v))) }
    if let v = c.account { ACCOUNT = v }
    if let v = c.tz { TZ_ID = v }
    if let v = c.backgroundOpacity { BG_OPACITY = max(0, min(1, CGFloat(v))) }
    if let v = c.leafPath, !v.isEmpty { LEAF_PATH = v }
    print("[caldash] config: gap=\(GAP) monthZoom=\(MONTH_ZOOM) weekZoom=\(WEEK_ZOOM) u/\(ACCOUNT) \(TZ_ID) opacity=\(BG_OPACITY) leaf=\(LEAF_PATH)")
    print("[caldash] layout: leftColumnRatio=\(LEFT_COLUMN_RATIO.map { "\($0)" } ?? "nil(3等幅)") rightTopRatio=\(RIGHT_TOP_RATIO) nextWeekZoomScale=\(NEXT_WEEK_ZOOM_SCALE)")
    if let ref = REFERENCE_WIDTH {
        print("[caldash] formula: baseMonthZoom=\(BASE_MONTH_ZOOM ?? MONTH_ZOOM) baseWeekZoom=\(BASE_WEEK_ZOOM ?? WEEK_ZOOM) referenceWidth=\(ref)")
    }
}

// 解像度スケール式（sqrt ダンパー）。base * sqrt(ref/current)。
// 現画面が ref より狭い→zoom↑（文字↑）、広い→zoom↓（密度↑）。sqrt で振れ幅を抑える。
func effectiveZoom(base: CGFloat, ref: CGFloat, current: CGFloat) -> CGFloat {
    return base * (ref / max(1, current)).squareRoot()
}

func cal() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: TZ_ID) ?? .current
    return c
}
func nextWeekYMD() -> (Int, Int, Int) {
    let d = cal().date(byAdding: .day, value: 7, to: Date())!
    let c = cal().dateComponents([.year, .month, .day], from: d)
    return (c.year!, c.month!, c.day!)
}
// 4 pane（GridView.layout の panes[0..3] と順序を揃える）:
//   [0] 4週カスタム (左・全高) / [1] todo (右下・URL なし) / [2] 今週 (中央・全高) / [3] 来週 (右上)
// [0] の /customweek は日付を持たず常に今週始まり（本体のカスタムビュー設定=4週・月曜始まり）。
// [1] は Web でなくローカル描画なので nil（TodoPane が担当）。
func paneURLs() -> [String?] {
    let base = "https://calendar.google.com/calendar/u/\(ACCOUNT)/r"
    let (wy, wm, wd) = nextWeekYMD()
    return [
        "\(base)/customweek",             // 4週（今週始まり）
        nil,                               // todo（TodoPane）
        "\(base)/week",                   // 今週
        "\(base)/week/\(wy)/\(wm)/\(wd)"   // 来週
    ]
}

// ---- ANSI → HTML BEGIN（単体テスト用に sed で切り出せるよう、この範囲は Foundation のみに依存）----
// leaf --inline ansi の出力（SGR 主体）を <span style> 付き HTML に変換する。
// 対応: 0 / 1 / 2 / 3 / 4 / 22 / 23 / 24 / 30-37 / 90-97 / 39 / 40-47 / 100-107 / 49 /
//       38;5;n / 48;5;n / 38;2;r;g;b / 48;2;r;g;b。SGR 以外の CSI（カーソル移動等）と OSC は読み捨て。
// 色は属性ごと保持して「状態が変わったら span を閉じて開き直す」素朴方式（出力が小さいので十分）。
func ansi256(_ n: Int) -> String {
    let std: [(Int, Int, Int)] = [
        (0,0,0), (205,49,49), (13,188,121), (229,229,16), (36,114,200), (188,63,188), (17,168,205), (204,204,204),
        (102,102,102), (241,76,76), (35,209,139), (245,245,67), (59,142,234), (214,112,214), (41,184,219), (255,255,255)]
    var r = 0, g = 0, b = 0
    if n < 16 { (r, g, b) = std[max(0, n)] }
    else if n < 232 {
        let i = n - 16, lv = [0, 95, 135, 175, 215, 255]
        r = lv[i / 36]; g = lv[(i / 6) % 6]; b = lv[i % 6]
    } else { let v = 8 + (min(n, 255) - 232) * 10; r = v; g = v; b = v }
    return "rgb(\(r),\(g),\(b))"
}
func htmlEscape(_ s: String) -> String {
    var o = ""
    for ch in s {
        switch ch {
        case "&": o += "&amp;"
        case "<": o += "&lt;"
        case ">": o += "&gt;"
        default: o.append(ch)
        }
    }
    return o
}
func ansiToHTML(_ input: String) -> String {
    var fg: String? = nil, bg: String? = nil
    var bold = false, dim = false, italic = false, underline = false
    var out = "", run = ""
    func flush() {
        if run.isEmpty { return }
        var st: [String] = []
        if let f = fg { st.append("color:\(f)") }
        if let b = bg { st.append("background:\(b)") }
        if bold { st.append("font-weight:bold") }
        if dim { st.append("opacity:.55") }
        if italic { st.append("font-style:italic") }
        if underline { st.append("text-decoration:underline") }
        let t = htmlEscape(run)
        out += st.isEmpty ? t : "<span style=\"\(st.joined(separator: ";"))\">\(t)</span>"
        run = ""
    }
    func sgr(_ ps: [Int]) {
        var i = 0
        let p = ps.isEmpty ? [0] : ps
        while i < p.count {
            let c = p[i]
            switch c {
            case 0: fg = nil; bg = nil; bold = false; dim = false; italic = false; underline = false
            case 1: bold = true
            case 2: dim = true
            case 3: italic = true
            case 4: underline = true
            case 22: bold = false; dim = false
            case 23: italic = false
            case 24: underline = false
            case 30...37: fg = ansi256(c - 30)
            case 90...97: fg = ansi256(c - 90 + 8)
            case 39: fg = nil
            case 40...47: bg = ansi256(c - 40)
            case 100...107: bg = ansi256(c - 100 + 8)
            case 49: bg = nil
            case 38, 48:
                var col: String? = nil
                if i + 2 < p.count, p[i + 1] == 5 { col = ansi256(p[i + 2]); i += 2 }
                else if i + 4 < p.count, p[i + 1] == 2 {
                    col = "rgb(\(min(255, p[i + 2])),\(min(255, p[i + 3])),\(min(255, p[i + 4])))"; i += 4
                }
                if let col = col { if c == 38 { fg = col } else { bg = col } }
            default: break
            }
            i += 1
        }
    }
    let u = Array(input.unicodeScalars)
    var i = 0
    while i < u.count {
        let ch = u[i]
        if ch.value == 0x1B, i + 1 < u.count {
            let n = u[i + 1]
            if n == "[" {                       // CSI: ESC [ params final(0x40-0x7E)
                var j = i + 2, params = ""
                while j < u.count, !(u[j].value >= 0x40 && u[j].value <= 0x7E) { params.unicodeScalars.append(u[j]); j += 1 }
                if j < u.count {
                    if u[j] == "m" {
                        flush()
                        let ps = params.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ";" || $0 == ":" })
                            .map { Int($0) ?? 0 }
                        sgr(params.isEmpty ? [] : ps)
                    }
                    i = j + 1
                } else { i = u.count }
                continue
            } else if n == "]" {                // OSC: BEL か ST(ESC \) まで読み捨て
                var j = i + 2
                while j < u.count, u[j].value != 0x07, !(u[j].value == 0x1B && j + 1 < u.count && u[j + 1] == "\\") { j += 1 }
                i = (j < u.count && u[j].value == 0x1B) ? j + 2 : j + 1
                continue
            } else { i += 2; continue }         // その他 2 バイト ESC 列
        }
        if ch == "\r" { i += 1; continue }
        run.unicodeScalars.append(ch)
        i += 1
    }
    flush()
    return out
}
// ---- ANSI → HTML END ----

// todo パネル（pane [1]）。1 screen に 1 個。TodoWebView が自身の layout() で refresh を呼ぶので
// リサイズにも追随（実処理は key 比較で冪等）。AppDelegate の 2 秒タイマーも同じ refresh を叩く。
final class TodoWebView: WKWebView {
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
}

let TODO_FONT_PX: CGFloat = 16     // CSS px（pageZoom が掛かる）
let TODO_CHAR_W: CGFloat = 0.61    // 等幅の 1 字幅 ≒ 0.6em（SF Mono/Menlo は 0.602em。切れ防止に僅かに多め）
let TODO_PAD: CGFloat = 8          // CSS px（左右）

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
func expandTilde(_ p: String) -> String { (p as NSString).expandingTildeInPath }

// 日付 → ~/Store/30_Work/todo/YYYY/YYYYMMDD-todo.md
func todoPath(for date: Date) -> (path: String, stamp: String) {
    let c = cal().dateComponents([.year, .month, .day], from: date)
    let stamp = String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    return ("\(expandTilde(TODO_DIR))/\(String(format: "%04d", c.year!))/\(stamp)-todo.md", stamp)
}
// 当日ファイルが無いとき用: stamp 以下で最新の YYYYMMDD-todo.md（年ディレクトリ降順に探す）。
func latestTodoFile(onOrBefore stamp: String) -> (path: String, stamp: String)? {
    let fm = FileManager.default, root = expandTilde(TODO_DIR)
    let years = ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { $0.count == 4 && Int($0) != nil }.sorted(by: >)
    for y in years {
        let files = ((try? fm.contentsOfDirectory(atPath: "\(root)/\(y)")) ?? [])
            .filter { $0.count == 16 && $0.hasSuffix("-todo.md") && Int($0.prefix(8)) != nil && String($0.prefix(8)) <= stamp }
            .sorted(by: >)
        if let f = files.first { return ("\(root)/\(y)/\(f)", String(f.prefix(8))) }
    }
    return nil
}

// ---- todo の素朴レンダラ + 鮮度警告（leaf 無し用・純関数。単体テスト対象）----
// markdown を leaf 風の等幅 HTML（<pre> の中身）にする。入力は必ず HTML エスケープする。
func plainMarkdownToHTML(_ md: String) -> String {
    var lines: [String] = []
    for raw in md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
        // 先頭の空白（字下げ）を保ち、その後ろだけを解釈する
        let indentCount = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = String(raw.prefix(indentCount)), rest = String(raw.dropFirst(indentCount))
        if rest.hasPrefix("#") {
            let text = rest.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            lines.append("\(htmlEscape(indent))<b>\(htmlEscape(text))</b>")
        } else if rest.hasPrefix("- [ ] ") {
            lines.append("\(htmlEscape(indent))☐ \(htmlEscape(String(rest.dropFirst(6))))")
        } else if rest.hasPrefix("- [x] ") || rest.hasPrefix("- [X] ") {
            lines.append("\(htmlEscape(indent))<span style=\"color:#6b9e78\">☑ \(htmlEscape(String(rest.dropFirst(6))))</span>")
        } else {
            lines.append(htmlEscape(raw))
        }
    }
    return lines.joined(separator: "\n")
}
// 鮮度警告文。staleMin<=0 なら無効。.synced の mtime（nil=無い）が staleMin 分より古い/無いときだけ返す。
func staleBanner(syncedAt: Date?, now: Date, staleMin: Int) -> String? {
    guard staleMin > 0 else { return nil }
    if let t = syncedAt, now.timeIntervalSince(t) <= Double(staleMin) * 60 { return nil }
    guard let t = syncedAt else { return "last sync never (ogasawara unreachable?)" }
    let c = cal().dateComponents([.hour, .minute], from: t)
    return String(format: "last sync %02d:%02d (ogasawara unreachable?)", c.hour!, c.minute!)
}

final class TodoPane {
    let web: TodoWebView
    private var lastKey = ""
    private var lastErr = ""
    private var gen = 0            // 古い描画結果が新しいのを上書きしないための世代
    private let queue = DispatchQueue(label: "caldash.todo")

    init(zoom: CGFloat) {
        let cfg = WKWebViewConfiguration()
        web = TodoWebView(frame: .zero, configuration: cfg)
        web.pageZoom = zoom
        if #available(macOS 13.3, *) { web.isInspectable = !WALLPAPER }
        web.onLayout = { [weak self] in self?.refresh() }
    }

    // 今表示すべき (パス, 注記)。当日 → 無ければ最新の過去 → 無ければ nil。
    private func target() -> (path: String, note: String?)? {
        let today = todoPath(for: Date())
        if FileManager.default.fileExists(atPath: today.path) { return (today.path, nil) }
        if let l = latestTodoFile(onOrBefore: today.stamp) {
            let m = Int(l.stamp.dropFirst(4).prefix(2))!, d = Int(l.stamp.suffix(2))!
            return (l.path, "showing \(m)/\(d) (today's file not created yet)")
        }
        return nil
    }

    func refresh() {
        let zoom = web.pageZoom
        let width = web.bounds.width
        guard width > 0 else { return }
        let cols = max(20, Int(floor((width / zoom - 2 * TODO_PAD) / (TODO_FONT_PX * TODO_CHAR_W))))
        guard let t = target() else {
            let key = "none|\(zoom)"
            if key != lastKey { lastKey = key; gen += 1; show(body: "", note: "no todo file for today") }
            return
        }
        let mtime = ((try? FileManager.default.attributesOfItem(atPath: t.path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        // 鮮度警告は .synced の mtime と「今が古いか」で変わるので key に含める（2 秒 tick で再評価される）
        let synced = (try? FileManager.default.attributesOfItem(atPath: "\(expandTilde(TODO_DIR))/.synced"))?[.modificationDate] as? Date
        let banner = staleBanner(syncedAt: synced, now: Date(), staleMin: TODO_STALE_MIN)
        let key = "\(t.path)|\(mtime)|\(cols)|\(zoom)|\(banner ?? "")"
        if key == lastKey { return }
        lastKey = key; gen += 1
        let g = gen, leaf = expandTilde(LEAF_PATH), path = t.path
        let note = [banner, t.note].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
        queue.async { [weak self] in
            let r = TodoPane.runLeaf(leaf: leaf, cols: cols, file: path)
            DispatchQueue.main.async {
                guard let self = self, g == self.gen else { return }
                switch r {
                case .ok(let ansi):
                    self.lastErr = ""
                    print("[caldash] todo re-render \(path) cols=\(cols)")
                    self.show(body: ansiToHTML(ansi), note: note)
                case .fail(let msg):
                    // leaf 無し/失敗は正常系: 自前で素朴に描く。エラーを出すのはファイルが読めないときだけ。
                    // key は残す（leaf を後から置いた場合は mtime/再起動で戻る。毎 tick の再試行はしない）。
                    if msg != self.lastErr { print("[caldash] todo leaf unavailable, plain render: \(msg)"); self.lastErr = msg }
                    if let data = FileManager.default.contents(atPath: path) {
                        self.show(body: plainMarkdownToHTML(String(decoding: data, as: UTF8.self)), note: note)
                    } else {
                        self.lastKey = ""
                        self.show(body: "", note: "cannot read \(path)")
                    }
                }
            }
        }
    }

    enum LeafResult { case ok(String), fail(String) }
    static func runLeaf(leaf: String, cols: Int, file: String) -> LeafResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: leaf)
        p.arguments = ["--inline", "ansi:\(cols)", file]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return .fail("cannot run \(leaf): \(error.localizedDescription)") }
        // 万一ハングしても面が固まらないよう 10 秒で打ち切る。
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if p.isRunning { p.terminate() } }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let m = String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .fail("exit \(p.terminationStatus)" + (m.isEmpty ? "" : ": \(m)"))
        }
        return .ok(String(decoding: o, as: UTF8.self))
    }

    private func show(body: String, note: String?) {
        let n = (note ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
            .map { "<div class=\"dim\">\(htmlEscape($0))</div>" }.joined()
        let html = """
        <!doctype html><meta charset="utf-8"><style>
        html,body{margin:0;background:#0f1117;overflow:hidden}
        body{padding:\(Int(TODO_PAD))px}
        pre{margin:0;font:\(Int(TODO_FONT_PX))px/1.35 "SF Mono",Menlo,monospace;color:#d0d2da;white-space:pre}
        .dim{font:\(Int(TODO_FONT_PX))px/1.35 "SF Mono",Menlo,monospace;color:#646470}
        </style><body>\(n)<pre>\(body)</pre>
        """
        web.loadHTMLString(html, baseURL: nil)
    }
}

// 4週カスタムビュー（pane [0]）専用 JS（wallpaper 専用）。today 強調だけ行う。
// 月ビュー同様 today セルに .F262Ye が付く保証が無い（CSS では当てられない）ので、
// 「today は先頭の週行にいる・列＝月曜からの日数（本体設定=月曜始まり）」という
// 構造から特定し、背面オーバーレイ（行の全高×セルの列幅）を敷き、週ビューの today 列と同色 rgba(66,133,244,.15) で塗る。
// 週行は role=row 配下の gridcell 7 個で拾う（行数は 4 前後・親ごと最大グループ）。
// 位置演算と実測の日番号が合わない（ビューがまだ今週始まりでない等）ときは塗らない。
func customWeekPaneJS() -> String {
    return #"""
    (() => {
      const dayNum = c => {
        const t = (c.querySelector('h2') || c).textContent || '';
        const jp = t.match(/(\d+)日/);
        if (jp) return +jp[1];
        const all = t.match(/\d+/g);
        return all ? +all[all.length - 1] : NaN;
      };
      const apply = () => {
        const cells = [...document.querySelectorAll("[role='main'] [role='gridcell']")];
        const groups = new Map();
        for (const c of cells) {
          const r = c.closest("[role='row']");
          if (!r || !r.parentElement) continue;
          if (!groups.has(r.parentElement)) groups.set(r.parentElement, new Set());
          groups.get(r.parentElement).add(r);
        }
        let rows = [];
        for (const g of groups.values()) {
          const arr = [...g].filter(r => r.getBoundingClientRect().width > 0);
          if (arr.length > rows.length) rows = arr;
        }
        if (!rows.length) return;
        const now = new Date();
        const row = rows[0];
        const cell = row.querySelectorAll("[role='gridcell']")[(now.getDay() + 6) % 7];  // 月曜=0
        if (!cell || dayNum(cell) !== now.getDate()) return;
        let ov = row.querySelector(':scope > .caldash-today-ov');
        if (!ov) {
          ov = document.createElement('div');
          ov.className = 'caldash-today-ov';
          ov.style.position = 'absolute';
          ov.style.top = '0';
          ov.style.height = '100%';
          ov.style.pointerEvents = 'none';
          ov.style.backgroundColor = 'rgba(66, 133, 244, 0.15)';
          if (getComputedStyle(row).position === 'static') row.style.position = 'relative';
          row.insertBefore(ov, row.firstChild);
        }
        const rr = row.getBoundingClientRect(), cr = cell.getBoundingClientRect();
        ov.style.left = (cr.left - rr.left) + 'px';
        ov.style.width = cr.width + 'px';
      };
      apply();
      setInterval(apply, 3000);
    })();
    """#
}

// Google 一族のホストか（M1: 無人常駐で認証 view を外部 URL に飛ばさせない allowlist）
func isGoogleHost(_ host: String?) -> Bool {
    guard let h = host else { return true }
    let owned = ["google.com", "gstatic.com", "googleapis.com", "googleusercontent.com", "youtube.com"]
    return owned.contains { h == $0 || h.hasSuffix("." + $0) }
}

// 3 カラム、右は 来週(上)+todo(下) を縦スタック。左 4週・中央 今週は全高。middleExtraWidth が >0 なら中央 pane がその分広く、
// 左右 pane は残りを等分する（左 lw + 中央 lw+extra + 右 lw + gap*2 = W）。
// extra は AppDelegate が「中央 pane の hour gutter を左右 pane と day col 幅で
// 揃えるためのオフセット」として設定する。isFlipped=true で左上原点。
//
// leftColumnRatio（config）が入っていると 3 等幅をやめ、左カラムを usable*ratio に
// 固定して、残り全部を週ペイン 2 枚で分ける（0.3333 なら実質 3 等幅）。中央は依然 extra 分だけ広い
// （= 週 2 枚の day col 幅が揃う）という不変条件は両モードで保つ。
final class GridView: NSView {
    var panes: [NSView] = []
    var middleExtraWidth: CGFloat = 0
    var leftColumnRatio: CGFloat? = nil
    var rightTopRatio: CGFloat = 0.5
    private var lastLayoutLog = ""
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        guard panes.count == 4 else { return }
        let W = bounds.width, H = bounds.height
        let usable = max(0, W - 2 * GAP)
        let lw: CGFloat, mw: CGFloat, rw: CGFloat
        if let ratio = leftColumnRatio {
            lw = max(0, min(usable, usable * ratio))
            let rest = usable - lw                       // 週 2 枚の取り分
            rw = max(0, (rest - middleExtraWidth) / 2)
            mw = rest - rw                               // 差で出して丸め残りを消す
        } else {
            lw = max(0, (usable - middleExtraWidth) / 3)
            mw = lw + middleExtraWidth
            rw = lw
        }
        let topH = max(0, (H - GAP) * rightTopRatio)
        let botH = max(0, H - GAP - topH)
        let rx = lw + GAP + mw + GAP
        panes[0].frame = NSRect(x: 0,           y: 0,          width: lw, height: H)    // 4週（左・全高）
        panes[1].frame = NSRect(x: rx,          y: topH + GAP, width: rw, height: botH) // todo（右下）
        panes[2].frame = NSRect(x: lw + GAP,    y: 0,          width: mw, height: H)    // 今週（中央・全高、+extra）
        panes[3].frame = NSRect(x: rx,          y: 0,          width: rw, height: topH) // 来週（右上）
        // 幾何の証跡: rect/zoom が変わったときだけ 1 行（毎 layout では出さない）
        let names = ["4wk", "todo", "this", "next"]
        let line = panes.enumerated().map { (i, v) -> String in
            let z = (v as? WKWebView)?.pageZoom ?? 0
            let f = v.frame
            return "\(names[i])=(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) z=\(String(format: "%.3f", Double(z))))"
        }.joined(separator: " ")
        if line != lastLayoutLog { lastLayoutLog = line; print("[caldash] layout \(Int(W))x\(Int(H)): \(line)") }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {
    // wallpaper mode: 各 NSScreen に 1 window ずつ描画（cp-dash と同型）。
    // interactive mode: windows.count == 1（中央窓 1 本のみ）。
    // 3 配列は screen index で揃える（webs[i] は screen i の 4 pane）。
    var windows: [NSWindow] = []
    var grids: [GridView] = []
    var webs: [[WKWebView]] = []
    var todoPanes: [TodoPane] = []      // screen ごとに 1 個（pane [1]）
    var todoTimer: Timer?               // 2 秒ポーリング（TodoPane.refresh は key 比較で冪等）
    let store = WKWebsiteDataStore.default()   // ログイン共有＆永続（実測済み）

    // desktop-switch からの信号ハンドラ（wallpaper mode 限定）。retain 必須。
    // 生の signal(2) は async-signal-safe な API しか呼べず NSWindow 不可なので
    // DispatchSource で main queue に配信して安全にウィンドウ操作する。
    var switchSource: DispatchSourceSignal?

    // 式モードか（REFERENCE_WIDTH 指定時のみ）
    var formulaMode: Bool { REFERENCE_WIDTH != nil }

    // 指定 screen 幅から effective zoom を算出。式 off なら config の静的値を返す。
    func computeEffectiveZooms(for screen: NSScreen) -> (CGFloat, CGFloat) {
        guard let ref = REFERENCE_WIDTH else { return (MONTH_ZOOM, WEEK_ZOOM) }
        let baseM = BASE_MONTH_ZOOM ?? MONTH_ZOOM
        let baseW = BASE_WEEK_ZOOM ?? WEEK_ZOOM
        let w = screen.frame.width
        return (effectiveZoom(base: baseM, ref: ref, current: w),
                effectiveZoom(base: baseW, ref: ref, current: w))
    }

    func makeWeb(_ urlStr: String, zoom: CGFloat, extraCSS: String = "", extraJS: String = "") -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store
        // M2: 無人常駐では JS の自動 window.open を禁止。ログインは gesture 起点なので interactive では許可。
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = !WALLPAPER
        // wallpaper mode 限定: 盤面だけ残す CSS を毎ロード注入（documentElement 直下なので
        // SPA の DOM 再構築で剥がれない）。extraCSS で pane 固有ルール（例: 来週の時間軸
        // オフ）を後付けできる。interactive では UI 温存でログイン導線を確保。
        if WALLPAPER {
            let css = HIDE_CHROME_CSS + "\n" + extraCSS
            // MutationObserver で document.head を監視、style 要素が消えたら即再注入。
            // 日次 reanchor での URL 再読込では atDocumentEnd で毎回再発火するので、
            // ここで確保するのは「同一ページ内で Google が SPA 的に head を弄っても
            // CSS を失わない」保険。observer が万一漏らしても setInterval で数秒後に復旧。
            let js = """
            (() => {
              const CSS = `\(css)`;
              const inject = () => {
                if (document.getElementById('caldash-hide-chrome')) return;
                const s = document.createElement('style');
                s.id = 'caldash-hide-chrome';
                s.textContent = CSS;
                (document.head || document.documentElement).appendChild(s);
              };
              inject();
              // head の childList 変化を監視。head 自体が置換されたら subtree で拾えないので
              // documentElement を root にして childList を見る（head/body 置換にも耐える）。
              new MutationObserver(inject).observe(document.documentElement, { childList: true, subtree: false });
              new MutationObserver(inject).observe(document.head || document.documentElement, { childList: true });
              // 保険: 3 秒毎に生存チェック（observer が漏らしても最大 3 秒で復旧）。
              setInterval(inject, 3000);
            })();
            """
            let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            cfg.userContentController.addUserScript(script)
            // pane 固有の JS（例: 月ペインの境界週デデュープ）。CSS と同じく wallpaper 限定。
            if !extraJS.isEmpty {
                cfg.userContentController.addUserScript(
                    WKUserScript(source: extraJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
        }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.customUserAgent = SAFARI_UA
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.pageZoom = zoom
        // H2: 認証済み Google セッションに Inspector を残さない（無人常駐では無効）。
        if #available(macOS 13.3, *) { wv.isInspectable = !WALLPAPER }
        wv.load(URLRequest(url: URL(string: urlStr)!))
        return wv
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        if WALLPAPER {
            setupWallpaperWindows()
            // 解像度/モニタ挿抜/main 切替を購読。screen 数の変化なら全再構築、
            // 数同じ（解像度変更のみ）なら zoom + frame を追随。
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.reapplyForCurrentScreens()
            }
            // desktop-switch IPC: SIGUSR1 で ~/.local/state/desktop-switch/cmd を読み、
            // 該当 screen だけ show/hide する（引数を渡せない signal の穴埋め）。
            // 生 signal(2) は default で終了なので事前に SIG_IGN で無効化してから
            // DispatchSource で main queue に配信して NSWindow を安全に操作。
            signal(SIGUSR1, SIG_IGN)
            switchSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            switchSource?.setEventHandler { [weak self] in self?.handleSwitchCommand() }
            switchSource?.resume()
            // launchctl kickstart 経由の再起動でも表示状態を保つため、起動時に state を
            // 読んで各 window の visibility を復元。state 無い（初回）なら全 screen 見せる。
            applyPersistedState()
        } else {
            // Interactive: 中央 1 窓に 4 pane grid。login/デバッグ用。
            let initialScreen = NSScreen.main ?? NSScreen.screens[0]
            let (z, wz) = computeEffectiveZooms(for: initialScreen)
            let (grid, paneWebs) = makeGrid(screenFrame: NSRect(x: 0, y: 0, width: 1800, height: 1050),
                                            zoom: z, weekZoom: wz)
            let w = NSWindow(contentRect: grid.frame,
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "caldash — 4週/todo/今週/来週（--wallpaper で常在面化）"
            w.contentView = grid
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            windows = [w]
            grids = [grid]
            webs = [paneWebs]
        }
        scheduleDailyReanchor()
        startStretchTimer()
        todoTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.todoPanes.forEach { $0.refresh() }
        }
    }

    // GridView + 4 pane を組み立てて (grid, webs) を返す。呼び出し側で
    // self.grids/self.webs に append（screen index を揃えるため）。
    private func makeGrid(screenFrame: NSRect, zoom: CGFloat, weekZoom: CGFloat) -> (GridView, [WKWebView]) {
        let grid = GridView(frame: screenFrame)
        grid.wantsLayer = true
        // pane 間 GAP を黒で埋める（透過は window.alphaValue で全体一律にかけるので
        // ここは触らない）。
        grid.layer?.backgroundColor = NSColor.black.cgColor
        grid.autoresizingMask = [.width, .height]
        // 中央 pane (今週) の hour gutter 分を余分に幅取って左右と day col 幅を揃える。
        // pageZoom が掛かるので device px = CSS px * weekZoom。
        grid.middleExtraWidth = GCAL_WEEK_GUTTER_PX * weekZoom
        grid.leftColumnRatio = LEFT_COLUMN_RATIO
        grid.rightTopRatio = RIGHT_TOP_RATIO
        let zooms: [CGFloat] = [zoom, zoom * TODO_ZOOM_SCALE, weekZoom, weekZoom * NEXT_WEEK_ZOOM_SCALE]  // 4週/todo/今週/来週（todo は月 zoom・来週は縮小）
        // 来週 (index 3) は時間ラベル gutter を完全に消去し、day headers も events grid
        // 本体も左端に寄せる。GCal 週ビュー DOM (2026-07-30 時点):
        //   .UqLcs  = 上部 Texas/Japan チップコンテナ（.sS0sZd + .kL3bhb 内包）
        //   .FDbe8b = day headers / all-day 行の左端 spacer（時間 gutter 幅を予約）
        //   .EDDeke = events grid 行の左端 spacer
        //   .lqYlwe = hour 列コンテナ（.R6TFwe 内包）。JS が 96px 固定 width を設定するので
        //             R6TFwe だけ hide しても 96px 残る → 親ごと display:none で潰す。
        //             .lqYlwe と .mDPmMe（events grid）は .uEzZIb の flex sibling なので
        //             .lqYlwe を消せば .mDPmMe が全幅（96px 分左へ）に広がる。
        // NOTE: Google の class 名はハッシュで release 毎に変わる可能性あり（fragile）。
        //       壊れたら wallpaper mode で isInspectable=true にして再インスペクト。
        // 4週ペインは today 強調のみ（customWeekPaneJS）。todo ペイン（[1]）は Web 注入なし。
        let extraCSSs: [String] = ["", "", WEEK_EVENT_FONT_CSS,
            WEEK_EVENT_FONT_CSS + "\n.lqYlwe, .UqLcs, .FDbe8b, .EDDeke { display: none !important; }"]
        let extraJSs: [String] = [customWeekPaneJS(), "", WEEK_STRETCH_JS, WEEK_STRETCH_JS]
        let urls = paneURLs()
        let paneWebs: [WKWebView] = urls.indices.map { i in
            if let u = urls[i] { return makeWeb(u, zoom: zooms[i], extraCSS: extraCSSs[i], extraJS: extraJSs[i]) }
            let tp = TodoPane(zoom: zooms[i])
            todoPanes.append(tp)
            return tp.web
        }
        grid.panes = paneWebs
        paneWebs.forEach { grid.addSubview($0) }
        return (grid, paneWebs)
    }

    // wallpaper mode: NSScreen.screens をループして各 screen に 1 window ずつ生成。
    // 呼び出し前に windows/grids/webs をクリアしておくこと（reapplyForCurrentScreens
    // の全再構築パスで再利用される）。
    private func setupWallpaperWindows() {
        for (i, screen) in NSScreen.screens.enumerated() {
            // visibleFrame は menu bar と dock を除外した領域。壁紙 level の window でも
            // menu bar の下に潜り込むと透過越しに calendar が menu bar に混じって
            // メニュー文字が読みにくくなる（透過運用で顕在化）。ここで避ける。
            let area = screen.visibleFrame
            let (zoom, weekZoom) = computeEffectiveZooms(for: screen)
            let (grid, paneWebs) = makeGrid(screenFrame: NSRect(origin: .zero, size: area.size),
                                            zoom: zoom, weekZoom: weekZoom)
            let w = NSWindow(contentRect: area, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.backgroundColor = .black
            // NSWindow.alphaValue で window 全体を一律に半透明化（compositor level）。
            // これで event card / 時刻軸 / grid line / 文字も含めて uniform に壁紙が透ける。
            // isOpaque は alpha<1 の時 false にしないと合成が壊れる。opacity=1.0 なら
            // isOpaque=true で描画パス最適化（AppKit が全画面 opaque 扱いで速い）。
            w.isOpaque = (BG_OPACITY >= 1.0)
            w.alphaValue = BG_OPACITY
            w.contentView = grid
            w.setFrame(area, display: true)
            w.orderFrontRegardless()
            windows.append(w)
            grids.append(grid)
            webs.append(paneWebs)
            print("[caldash] wallpaper screen[\(i)] visible=\(area.size) zoom=\(zoom)/\(weekZoom)")
        }
    }

    // ---- 週ペイン時間グリッド伸縮の状態読み出し（log 専用。pageZoom は触らない）----
    // ページ内 JS（WEEK_STRETCH_JS）が伸縮を自走する。ここは 2 秒毎に pageZoom を JS へ渡し（deadband の
    // device px 換算用）、状態を読んで「変化したときだけ」log する（同じ値の繰り返しは出さない）。
    var stretchTimer: Timer?
    var lastStretchKey: [String: String] = [:]
    func startStretchTimer() {
        guard WALLPAPER else { return }
        stretchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pollStretch() }
    }
    func pollStretch() {
        for (si, screenWebs) in webs.enumerated() where si < grids.count {
            for pi in [2, 3] where pi < screenWebs.count {
                let wv = screenWebs[pi]
                if wv.isLoading { continue }
                let z = wv.pageZoom
                let js = "window.__caldashZoom = \(z); JSON.stringify(window.__caldashStretch || null)"
                wv.evaluateJavaScript(js) { [weak self, weak wv] res, _ in
                    guard let self = self, let wv = wv, let str = res as? String,
                          let d = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
                          (d["applied"] as? Bool) == true,
                          let k = (d["k"] as? NSNumber)?.doubleValue,
                          let nat = (d["natural"] as? NSNumber)?.doubleValue,
                          let avail = (d["avail"] as? NSNumber)?.doubleValue else { return }
                    let zz = Double(wv.pageZoom)
                    let sz = self.grids[si].frame.size
                    let line = "[caldash] stretch week pane=\(pi) screen=\(si) \(Int(sz.width))x\(Int(sz.height)) k=\(String(format: "%.3f", k)) natural=\(Int((nat * zz).rounded())) avail=\(Int((avail * zz).rounded()))"
                    let key = "\(si)-\(pi)"
                    // 同じ k / 高さなら再出力しない（device px・k 3 桁で比較）
                    if self.lastStretchKey[key] == line { return }
                    self.lastStretchKey[key] = line
                    print(line)
                }
            }
        }
    }

    // 日次アンカー更新：ローカル 00:01 に全面を再ロード（todo 面は当日ファイルへ切替）。DST でずれないよう Calendar で厳密算出。
    func scheduleDailyReanchor() {
        guard let next = cal().nextDate(after: Date(),
                                        matching: DateComponents(hour: 0, minute: 1, second: 0),
                                        matchingPolicy: .nextTime) else { return }
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            self?.reanchor()
            self?.scheduleDailyReanchor()
        }
        RunLoop.main.add(t, forMode: .common)
        print("[caldash] next re-anchor at \(next)")
    }
    func reanchor() {
        let urls = paneURLs()   // 来週 URL は当日基準で再計算（4週は固定 URL＝再ロードで今週始まりに戻る）
        for screenWebs in webs {
            for (i, wv) in screenWebs.enumerated() where i < urls.count {
                if let s = urls[i], let u = URL(string: s) { wv.load(URLRequest(url: u)) }
            }
        }
        todoPanes.forEach { $0.refresh() }   // 日付が変わっていれば key（パス）が変わり再描画される
        print("[caldash] re-anchored across \(webs.count) screen(s)")
    }

    // 画面変化（モニタ挿抜・main 切替・解像度変更）に追随。screen 数が変わったら
    // 全 window を tear down して setupWallpaperWindows() で作り直し、同じなら
    // 各 window の frame と zoom を更新するだけ。interactive mode では no-op。
    func reapplyForCurrentScreens() {
        guard WALLPAPER else { return }
        let screens = NSScreen.screens
        if screens.count != windows.count {
            print("[caldash] screen count \(windows.count) → \(screens.count), rebuilding")
            for w in windows { w.orderOut(nil); w.close() }
            windows.removeAll(); grids.removeAll(); webs.removeAll(); todoPanes.removeAll()
            setupWallpaperWindows()
            return
        }
        for (i, w) in windows.enumerated() {
            guard let screen = w.screen ?? (i < screens.count ? screens[i] : nil) else { continue }
            let area = screen.visibleFrame
            if w.frame != area { w.setFrame(area, display: true) }
            guard formulaMode, i < webs.count else { continue }
            let (nz, nwz) = computeEffectiveZooms(for: screen)
            let zooms: [CGFloat] = [nz, nz * TODO_ZOOM_SCALE, nwz, nwz * NEXT_WEEK_ZOOM_SCALE]  // 4週/todo/今週/来週
            for (j, wv) in webs[i].enumerated() where j < zooms.count {
                if wv.pageZoom != zooms[j] { wv.pageZoom = zooms[j] }
            }
        }
    }

    // 与えた monitor-name に一致する NSScreen を持つ window の index を返す。
    // aerospace の monitor-name（例 "Mi TV" / "Built-in Display"）と NSScreen.localizedName
    // が同一なので照合可能。同名複数モニタは順に返す。
    private func windowIndices(matching name: String) -> [Int] {
        return windows.enumerated().compactMap { (i, w) in
            (w.screen?.localizedName == name) ? i : nil
        }
    }

    // 起動時に ~/.local/state/desktop-switch/state を読んで per-screen 表示状態を復元。
    // 書式: 各行 "<monitor-name>=<layer>"（layer=caldash/cp/wallpaper）。未記載の screen
    // は show で残す（初回起動 or 部分状態の互換）。reload（kickstart）後の状態保持のため必須。
    private func applyPersistedState() {
        let path = ("\(NSHomeDirectory())/.local/state/desktop-switch/state" as NSString).expandingTildeInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = String(parts[0]), layer = String(parts[1])
            for idx in windowIndices(matching: name) {
                if layer == "caldash" { windows[idx].orderFrontRegardless() }
                else                  { windows[idx].orderOut(nil) }
            }
        }
        print("[caldash] state restored from \(path)")
    }

    // desktop-switch IPC: SIGUSR1 で ~/.local/state/desktop-switch/cmd を読んで dispatch。
    // 書式は1行、"layer=<name>;screen=<monitor-name|all>"。layer が "caldash" なら該当
    // window を show、それ以外（cp/wallpaper）なら hide。screen=all は全 window に一括適用。
    // command file 不在 or parse 失敗は黙って noop（信号バタつきで壊さない）。
    private func handleSwitchCommand() {
        let path = ("\(NSHomeDirectory())/.local/state/desktop-switch/cmd" as NSString).expandingTildeInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var layer = "", screenSpec = ""
        for kv in line.split(separator: ";") {
            let parts = kv.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]), val = String(parts[1])
            if key == "layer" { layer = val }
            if key == "screen" { screenSpec = val }
        }
        let iShouldShow = (layer == "caldash")
        let targets: [Int] = (screenSpec == "all") ? Array(windows.indices) : windowIndices(matching: screenSpec)
        for idx in targets {
            if iShouldShow { windows[idx].orderFrontRegardless() }
            else           { windows[idx].orderOut(nil) }
        }
        print("[caldash] cmd layer=\(layer) screen=\(screenSpec) → \(iShouldShow ? "show" : "hide") \(targets.count) window(s)")
    }

    // M1: ポップアップ/新規窓を同 view に流す（サインイン用）。無人常駐では Google 一族のみ許可。
    func webView(_ w: WKWebView, createWebViewWith cfg: WKWebViewConfiguration,
                 for act: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = act.request.url, (!WALLPAPER || isGoogleHost(u.host)) { w.load(act.request) }
        return nil
    }
    // M1: 無人常駐では Google 一族以外の http(s) 遷移を遮断（認証 view の乗っ取り防止）。
    func webView(_ w: WKWebView, decidePolicyFor act: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if WALLPAPER, let u = act.request.url,
           (u.scheme == "http" || u.scheme == "https"), !isGoogleHost(u.host) {
            print("[caldash] blocked non-Google nav: \(u.absoluteString)")
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("[caldash] FAIL: \(e.localizedDescription)")
    }
    // desktop-switch の SIGUSR2 で window を orderOut するとここが呼ばれて終了→launchd 再起動
    // ループに入るため、wallpaper mode では false を返して常駐継続。interactive では終了して OK。
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { !WALLPAPER }
}

setvbuf(stdout, nil, _IONBF, 0)
loadConfig()
let app = NSApplication.shared
app.setActivationPolicy(WALLPAPER ? .accessory : .regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
