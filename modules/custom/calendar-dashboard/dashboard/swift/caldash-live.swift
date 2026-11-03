// caldash-live — カレンダー・ダッシュボード（本体 Google カレンダー×4面）
// 本体アプリを WKWebView で"最上位"ロード（iframe でないので X-Frame-Options 回避）。
// 全面が .default() データストア共有 → ログイン1回で全面認証・再起動で永続（実測済み）。
//
// レイアウト（4面）: 3 等幅カラム、右カラムだけ上下スタック（2026-10-02 ユーザー決定）。
//   ┌────────┬────────┬────────┐
//   │ 4週     │ 今週    │ 来週    │   ← 来週は縮小 zoom（nextWeekZoomScale）。上段 rightTopRatio
//   │ (全高)  │ (全高)  ├────────┤
//   │         │         │ Linear  │   ← Linear の Web UI（Google カレンダーではない面）
//   └────────┴────────┴────────┘
// WHY 右だけ分割: 4週ビューが既に「来週」を含むので、来週ペインは全高の大きさが要らない
//      （縮小 zoom で十分）。空いた右下を Linear に回すと、旧「左下の月ペイン半分」より広く取れる。
// WHY 3 カラム等幅: ユーザー要望「幅は全て同じように」。leftColumnRatio=1/3 で左を固定し、
//      残りを今週・来週で等分（中央だけ hour gutter 分 +extra＝日列幅を来週と揃える不変条件は維持）。
// WHY 来週の zoom を縮める: 高さが半分になるので、同じ zoom だと 0-24h がスクロール無しで収まらない。
//      週 zoom × nextWeekZoomScale（既定 0.75）。解像度スケール式は週 zoom 側に先に掛かるので、
//      画面ごとの補正の上に乗る（式 → 来週だけ倍率）。
// 左上は月ビューでなく Google カレンダーのカスタムビュー（4週・月曜始まり・本体設定済み）。
// WHY: 月ビューは月末で打ち切られ、翌月に入った週が見えなくなる。4週カスタムビューは
//      常に「今週」始まりなので、直近4週間が月境界に関係なく連続して見える（2026-10-02 ユーザー要望）。
//
// 右下は Linear パネル: Linear の Web UI（config: linearURL。既定 https://linear.app/treo-sample/team/LIF/active）を
//   Google 面と同じ WKWebView・同じ .default() データストアで読む（ログイン1回で永続）。
// WHY Web 面: todo-board（ローカル md を leaf で描画）を廃止し、タスクの正史を Linear に移した（2026-11）。
//      自前描画をやめて本体 SPA をそのまま出す。Google 用の CSS/JS 注入（クロム隠し・週伸縮・today 強調）は
//      この面には一切かけない（Linear 自前のダークテーマで読める）。
// wallpaper mode は ignoresMouseEvents なので閲覧専用。操作したいときは interactive（無フラグ）で開く。
//
// モード: （無フラグ）interactive=通常窓・ログイン用 / --wallpaper=常在面（アイコン裏・透過・全Space・無人）
// 設定: ~/calendar-dashboard/caldash-config.json（env CALDASH_CONFIG で上書き）。
//       gap / zoom / weekZoom / baseZoom / baseWeekZoom / referenceWidth /
//       leftColumnRatio（左カラム幅比。等幅なら 0.3333）/ rightTopRatio（右カラム上段=来週の高さ比。既定 0.5）/
//       nextWeekZoomScale（来週ペインだけ週 zoom に掛ける倍率。既定 0.75）/
//       linearZoomScale（Linear ペインだけ月 zoom に掛ける倍率。既定 1.3333。旧キー todoZoomScale も受理）/
//       linearURL（Linear 面の URL。既定 https://linear.app/treo-sample/team/LIF/active）/
//       account(u/N) / tz / backgroundOpacity。
// 日次: ローカル 00:01 に再ロード（各面を今日基準に再アンカー＋来週 URL 再計算・Linear 面も再ロード。
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
// 自動ログイン窓（wallpaper mode）:
//   WHY: ブラウザ（Chrome/Safari）の cookie は WKWebView と共有されない。Google/Linear のセッションが切れて
//   ペインが signin ページに飛ばされても、無人常駐では誰も気づかない。外部ブラウザでログインしても
//   .default() データストアには入らないので、同一プロセス内に通常窓（ログイン窓）を自動で開く。
//   検出: ペインの URL が accounts.google.com（Google）／ linear.app の /login・/signup（Linear）になったとき。
//   ログイン窓は 1 つだけ（複数サービスは順番に）。完了（calendar.google.com / linear.app 非ログイン面）で
//   自動で閉じ、該当サービスの全ペインを再読込。手動で閉じたら同サービスは 10 分間再オープンしない。
//   ログ・URL はクエリ無し（token 保護）。cookie は一切ログしない。資格情報は人間が入力する。
//
// セキュリティ（監査 2026-07-27 反映）:
//   - isInspectable / JS 自動 window.open は無人常駐(--wallpaper)では無効（認証 view への侵入面を絞る）。
//   - createWebViewWith / decidePolicy は wallpaper 時 Google 一族ホスト（＋Linear 面のみ linear.app 系）のみ許可（認証 view の外部誘導阻止）。
//   - .default() に本人の常時 Google セッション cookie が永続する点は自覚の上で受容（ブラウザ同等リスク。Linear も同様）。

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
// 右カラム（来週 / Linear の縦スタック）の上段=来週が占める高さ比（config: rightTopRatio）。
var RIGHT_TOP_RATIO: CGFloat = 0.5
// 来週ペインだけに掛ける zoom 倍率（config: nextWeekZoomScale）。式適用後の週 zoom に乗る。
var NEXT_WEEK_ZOOM_SCALE: CGFloat = 0.75
// Linear ペインだけに掛ける zoom 倍率（config: linearZoomScale。旧キー todoZoomScale も受理）。月 zoom に乗る。
// 既定 1.3333＝旧 todo 面と同じ（月 zoom 0.75 から zoom 1.0 相当・2026-10-02 本人指定）。
var LINEAR_ZOOM_SCALE: CGFloat = 1.3333
// 背景 alpha（config: backgroundOpacity）。1.0=完全不透明、<1.0 で壁紙が透ける。
// window.isOpaque + backgroundColor + GridView.layer + WKWebView.drawsBackground +
// CSS 注入の全レイヤーに一貫適用する（どこか一箇所でも opaque だと透過は死ぬ）。
var BG_OPACITY: CGFloat = 1.0
// Linear 面（pane [1]）の URL（config: linearURL）。Google 面と同じ .default() データストアで読むので
// ログインは1回で永続。既定は本人の Linear チーム LIF の active ビュー。
var LINEAR_URL = "https://linear.app/treo-sample/team/LIF/active"

struct Config: Codable {
    var gap: Double?; var monthZoom: Double?; var weekZoom: Double?
    var baseMonthZoom: Double?; var baseWeekZoom: Double?; var referenceWidth: Double?
    var leftColumnRatio: Double?; var rightTopRatio: Double?; var nextWeekZoomScale: Double?
    var linearZoomScale: Double?; var todoZoomScale: Double?   // todoZoomScale は旧キー（互換）
    var linearURL: String?
    var account: Int?; var tz: String?
    var backgroundOpacity: Double?
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
    if let v = c.linearZoomScale ?? c.todoZoomScale { LINEAR_ZOOM_SCALE = max(0.5, min(2.5, CGFloat(v))) }
    if let v = c.linearURL, !v.isEmpty, URL(string: v) != nil { LINEAR_URL = v }
    if let v = c.account { ACCOUNT = v }
    if let v = c.tz { TZ_ID = v }
    if let v = c.backgroundOpacity { BG_OPACITY = max(0, min(1, CGFloat(v))) }
    print("[caldash] config: gap=\(GAP) monthZoom=\(MONTH_ZOOM) weekZoom=\(WEEK_ZOOM) u/\(ACCOUNT) \(TZ_ID) opacity=\(BG_OPACITY) linear=\(LINEAR_URL)")
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
//   [0] 4週カスタム (左・全高) / [1] Linear (右下) / [2] 今週 (中央・全高) / [3] 来週 (右上)
// [0] の /customweek は日付を持たず常に今週始まり（本体のカスタムビュー設定=4週・月曜始まり）。
// [1] は Google ではなく Linear の Web UI（LINEAR_URL）。
func paneURLs() -> [String] {
    let base = "https://calendar.google.com/calendar/u/\(ACCOUNT)/r"
    let (wy, wm, wd) = nextWeekYMD()
    return [
        "\(base)/customweek",             // 4週（今週始まり）
        LINEAR_URL,                        // Linear
        "\(base)/week",                   // 今週
        "\(base)/week/\(wy)/\(wm)/\(wd)"   // 来週
    ]
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

// Linear のホストか（linear.app と任意のサブドメイン）。Linear 面（pane [1]）でだけ追加許可する。
// ログインは Google OAuth（Google 一族は許可済み）かメール/マジックリンク（linear.app 内で完結）。
// SAML SSO の IdP など上記以外へ飛ぶ構成だと wallpaper mode では遮断される（interactive では無制限）。
func isLinearHost(_ host: String?) -> Bool {
    guard let h = host else { return true }
    return h == "linear.app" || h.hasSuffix(".linear.app")
}

// 3 カラム、右は 来週(上)+Linear(下) を縦スタック。左 4週・中央 今週は全高。middleExtraWidth が >0 なら中央 pane がその分広く、
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
        panes[1].frame = NSRect(x: rx,          y: topH + GAP, width: rw, height: botH) // Linear（右下）
        panes[2].frame = NSRect(x: lw + GAP,    y: 0,          width: mw, height: H)    // 今週（中央・全高、+extra）
        panes[3].frame = NSRect(x: rx,          y: 0,          width: rw, height: topH) // 来週（右上）
        // 幾何の証跡: rect/zoom が変わったときだけ 1 行（毎 layout では出さない）
        let names = ["4wk", "linear", "this", "next"]
        let line = panes.enumerated().map { (i, v) -> String in
            let z = (v as? WKWebView)?.pageZoom ?? 0
            let f = v.frame
            return "\(names[i])=(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) z=\(String(format: "%.3f", Double(z))))"
        }.joined(separator: " ")
        if line != lastLayoutLog { lastLayoutLog = line; print("[caldash] layout \(Int(W))x\(Int(H)): \(line)") }
    }
}

// ── 自動ログイン窓 ───────────────────────────────────────────
enum LoginService: String {
    case google, linear
    var label: String { self == .google ? "Google" : "Linear" }
    var targetURL: String { self == .google ? paneURLs()[0] : LINEAR_URL }
    var paneIndices: [Int] { self == .google ? [0, 2, 3] : [1] }
}

func nowISO() -> String {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone.current
    f.formatOptions = [.withInternetDateTime, .withTimeZone]
    return f.string(from: Date())
}
// host+path（クエリ・フラグメントは捨てる）
func safeURLString(_ u: URL?) -> String { (u?.host ?? "?") + (u?.path ?? "") }

// URL からサービスのログイン要求ページか判定
func loginServiceNeeded(for u: URL?) -> LoginService? {
    guard let u = u, let h = u.host?.lowercased() else { return nil }
    if h == "accounts.google.com" { return .google }
    if h == "linear.app" || h.hasSuffix(".linear.app") {
        if u.path.hasPrefix("/login") || u.path.hasPrefix("/signup") { return .linear }
    }
    return nil
}
// ログイン窓内のページが「ログイン完了後の面」か
func loginCompleted(_ svc: LoginService, url u: URL?) -> Bool {
    guard let u = u, let h = u.host?.lowercased() else { return false }
    switch svc {
    case .google: return h == "calendar.google.com"
    case .linear: return (h == "linear.app" || h.hasSuffix(".linear.app"))
                         && !u.path.hasPrefix("/login") && !u.path.hasPrefix("/signup")
    }
}

// accessory アプリの窓でもキー入力（パスワード欄）を受けられるように明示。
final class LoginWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class LoginController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    var window: LoginWindow?
    var web: WKWebView?
    var current: LoginService?
    var queue: [LoginService] = []
    var lastDismissed: [LoginService: Date] = [:]   // 未完了で閉じられた時刻（10 分バックオフ）
    var completing = false
    var urlObservation: NSKeyValueObservation?   // SPA（Linear）の画面内遷移で完了を拾うため
    var reloadPanes: ((LoginService) -> Void)?
    static let backoff: TimeInterval = 600

    func request(_ svc: LoginService) {
        if let t = lastDismissed[svc], Date().timeIntervalSince(t) < LoginController.backoff { return }
        if window != nil {
            if svc != current && !queue.contains(svc) { queue.append(svc) }
            return
        }
        open(svc)
    }

    private func installMenuIfNeeded() {
        // メニューバーの無い accessory では ⌘V/⌘C が効かない。最小の Edit メニューを足す。
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit caldash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    private func open(_ svc: LoginService) {
        current = svc
        completing = false
        installMenuIfNeeded()
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()   // パネルと同じ cookie ストア
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.customUserAgent = SAFARI_UA
        wv.navigationDelegate = self
        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] w, _ in
            DispatchQueue.main.async {
                guard let self = self, let svc = self.current, loginCompleted(svc, url: w.url) else { return }
                self.complete(svc)
            }
        }
        wv.uiDelegate = self
        if #available(macOS 13.3, *) { wv.isInspectable = false }
        let rect = NSRect(x: 0, y: 0, width: 1100, height: 800)
        let w = LoginWindow(contentRect: rect,
                            styleMask: [.titled, .closable, .resizable, .miniaturizable],
                            backing: .buffered, defer: false)
        w.title = "caldash — ログインしてください（Google / Linear）"
        w.isReleasedWhenClosed = false
        w.level = .normal
        w.ignoresMouseEvents = false
        w.delegate = self
        w.contentView = wv
        w.setFrame(rect, display: false)
        (NSScreen.main ?? NSScreen.screens.first).map { s in
            let f = s.visibleFrame
            w.setFrameOrigin(NSPoint(x: f.midX - rect.width / 2, y: f.midY - rect.height / 2))
        }
        window = w; web = wv
        wv.load(URLRequest(url: URL(string: svc.targetURL)!))
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(wv)
        print("[caldash] login window opened: \(svc.rawValue) at \(nowISO())")
    }

    private func teardown() {
        urlObservation = nil
        web?.navigationDelegate = nil
        web?.uiDelegate = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil; web = nil; current = nil
    }

    private func complete(_ svc: LoginService) {
        guard !completing else { return }
        completing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.current == svc, let wv = self.web else { return }
            // SPA の後追いリダイレクトで login に戻った場合は完了扱いにしない
            guard loginCompleted(svc, url: wv.url) else { self.completing = false; return }
            self.window?.delegate = nil   // 手動クローズ扱い（windowWillClose）を避ける
            self.window?.close()
            print("[caldash] login completed: \(svc.rawValue) at \(nowISO())")
            self.lastDismissed[svc] = nil
            self.teardown()
            self.reloadPanes?(svc)
            self.queue.removeAll { $0 == svc }
            if let next = self.queue.first {
                self.queue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.request(next) }
            }
        }
    }

    // ログイン窓の webview: wallpaper allowlist は使わない（interactive 同様）
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        if let svc = current, loginCompleted(svc, url: w.url) { complete(svc) }
    }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("[caldash] login window FAIL: \(e.localizedDescription)")
    }
    // ポップアップは同 view に流す
    func webView(_ w: WKWebView, createWebViewWith cfg: WKWebViewConfiguration,
                 for act: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if act.request.url != nil { w.load(act.request) }
        return nil
    }

    func windowWillClose(_ n: Notification) {
        // 完了処理（complete）側は delegate を外してから閉じるので、ここに来るのは手動クローズ
        guard let svc = current else { return }
        print("[caldash] login window closed without completion: \(svc.rawValue) at \(nowISO())")
        lastDismissed[svc] = Date()
        let pending = queue
        queue = []
        teardown()
        // 待ち行列の別サービスは、未バックオフのものがあれば次に開く
        if let next = pending.first(where: { s in
            guard let t = lastDismissed[s] else { return true }
            return Date().timeIntervalSince(t) >= LoginController.backoff }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.request(next) }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {
    // wallpaper mode: 各 NSScreen に 1 window ずつ描画（cp-dash と同型）。
    // interactive mode: windows.count == 1（中央窓 1 本のみ）。
    // 3 配列は screen index で揃える（webs[i] は screen i の 4 pane）。
    var windows: [NSWindow] = []
    var grids: [GridView] = []
    var webs: [[WKWebView]] = []
    let store = WKWebsiteDataStore.default()   // ログイン共有＆永続（実測済み）
    let login = LoginController()               // 自動ログイン窓（wallpaper mode のみ使用）
    // ペインの URL 変化の監視。Linear は SPA で、ログアウト時もページは 200 で返り、画面内の
    // pushState で /login に移る（2026-11-03 実測）。ナビゲーションの delegate では拾えないので URL を KVO で見る。
    var urlObservations: [NSKeyValueObservation] = []

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

    func makeWeb(_ urlStr: String, zoom: CGFloat, extraCSS: String = "", extraJS: String = "", injectChrome: Bool = true) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store
        // M2: 無人常駐では JS の自動 window.open を禁止。ログインは gesture 起点なので interactive では許可。
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = !WALLPAPER
        // wallpaper mode 限定: 盤面だけ残す CSS を毎ロード注入（documentElement 直下なので
        // SPA の DOM 再構築で剥がれない）。extraCSS で pane 固有ルール（例: 来週の時間軸
        // オフ）を後付けできる。interactive では UI 温存でログイン導線を確保。
        if WALLPAPER && injectChrome {
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
            login.reloadPanes = { [weak self] svc in self?.reloadPanes(of: svc) }
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
            w.title = "caldash — 4週/Linear/今週/来週（--wallpaper で常在面化）"
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
        let zooms: [CGFloat] = [zoom, zoom * LINEAR_ZOOM_SCALE, weekZoom, weekZoom * NEXT_WEEK_ZOOM_SCALE]  // 4週/Linear/今週/来週（Linear は月 zoom×倍率・来週は縮小）
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
        // 4週ペインは today 強調のみ（customWeekPaneJS）。Linear ペイン（[1]）は Google 用の注入なし（Linear 自前のダークテーマのまま）。
        let extraCSSs: [String] = ["", "", WEEK_EVENT_FONT_CSS,
            WEEK_EVENT_FONT_CSS + "\n.lqYlwe, .UqLcs, .FDbe8b, .EDDeke { display: none !important; }"]
        let extraJSs: [String] = [customWeekPaneJS(), "", WEEK_STRETCH_JS, WEEK_STRETCH_JS]
        let urls = paneURLs()
        let paneWebs: [WKWebView] = urls.indices.map { i in
            makeWeb(urls[i], zoom: zooms[i], extraCSS: extraCSSs[i], extraJS: extraJSs[i], injectChrome: i != 1)
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
            for wv in paneWebs {
                urlObservations.append(wv.observe(\.url, options: [.new]) { [weak self] w, _ in
                    DispatchQueue.main.async { self?.checkLoginRequired(w) }
                })
            }
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

    // 日次アンカー更新：ローカル 00:01 に全面を再ロード（Linear 面も再ロードで可）。DST でずれないよう Calendar で厳密算出。
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
                if let u = URL(string: urls[i]) { wv.load(URLRequest(url: u)) }
            }
        }
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
            windows.removeAll(); grids.removeAll(); webs.removeAll(); urlObservations.removeAll()
            setupWallpaperWindows()
            return
        }
        for (i, w) in windows.enumerated() {
            guard let screen = w.screen ?? (i < screens.count ? screens[i] : nil) else { continue }
            let area = screen.visibleFrame
            if w.frame != area { w.setFrame(area, display: true) }
            guard formulaMode, i < webs.count else { continue }
            let (nz, nwz) = computeEffectiveZooms(for: screen)
            let zooms: [CGFloat] = [nz, nz * LINEAR_ZOOM_SCALE, nwz, nwz * NEXT_WEEK_ZOOM_SCALE]  // 4週/Linear/今週/来週
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

    // wallpaper mode の許可ホスト: 全面 Google 一族。Linear 面（pane [1]）だけ加えて linear.app 系。
    func isAllowedHost(_ host: String?, in w: WKWebView) -> Bool {
        if isGoogleHost(host) { return true }
        return webs.contains { $0.count > 1 && $0[1] === w } && isLinearHost(host)
    }
    // M1: ポップアップ/新規窓を同 view に流す（サインイン用）。無人常駐では Google 一族（＋Linear 面は linear.app 系）のみ許可。
    func webView(_ w: WKWebView, createWebViewWith cfg: WKWebViewConfiguration,
                 for act: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = act.request.url, (!WALLPAPER || isAllowedHost(u.host, in: w)) { w.load(act.request) }
        return nil
    }
    // M1: 無人常駐では 許可ホスト以外の http(s) 遷移を遮断（認証 view の乗っ取り防止）。
    func webView(_ w: WKWebView, decidePolicyFor act: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if WALLPAPER, let u = act.request.url,
           (u.scheme == "http" || u.scheme == "https"), !isAllowedHost(u.host, in: w) {
            print("[caldash] blocked non-allowlisted nav: \(u.absoluteString)")
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("[caldash] FAIL: \(e.localizedDescription)")
    }

    // ── ログイン切れ検出（wallpaper mode のみ）──
    func checkLoginRequired(_ w: WKWebView) {
        guard WALLPAPER, let svc = loginServiceNeeded(for: w.url) else { return }
        var name = "?", scr = -1
        let names = ["4wk", "linear", "this", "next"]
        for (i, row) in webs.enumerated() { if let k = row.firstIndex(where: { $0 === w }) { scr = i; name = names[k] } }
        guard scr >= 0 else { return }
        print("[caldash] login required: pane=\(name) screen=\(scr) url=\(safeURLString(w.url)) at \(nowISO())")
        login.request(svc)
    }
    func webView(_ w: WKWebView, didReceiveServerRedirectForProvisionalNavigation n: WKNavigation!) { checkLoginRequired(w) }
    func webView(_ w: WKWebView, didCommit n: WKNavigation!) { checkLoginRequired(w) }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { checkLoginRequired(w) }

    // ログイン完了後: 該当サービスの全 screen のペインを元 URL で再読込
    func reloadPanes(of svc: LoginService) {
        let urls = paneURLs()
        for row in webs {
            for k in svc.paneIndices where k < row.count {
                row[k].load(URLRequest(url: URL(string: urls[k])!))
            }
        }
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
