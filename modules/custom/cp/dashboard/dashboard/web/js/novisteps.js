const NOVI_TOPIC_GROUPS = [
	// 1. 線形データ構造の基本（数える・引く・積む）
	{ name: '1. 線形構造', slugs: [
		'bucket', 'map', 'set', 'stack', 'queue', 'run-length-encoding',
	] },
	// 2. 全探索（すべての土台。再帰→ビット→順列→候補の絞り込み）
	{ name: '2. 全探索', slugs: [
		'recursive-function', 'recursive-brute-force-search',
		'bitmask-brute-force-search', 'next-permutation-search',
		'number-theory-search',
	] },
	// 3. 数学基礎（整数論）
	{ name: '3. 数学基礎', slugs: [
		'prime-divisor-factorization', 'eatosthenes',
	] },
	// 4. 累積和（「毎回数え直さない」の第一歩）
	{ name: '4. 累積和', slugs: [
		'prefix-sum-fast-range-sums',
	] },
	// 5. 貪欲法（基本→交換論法の各型）
	{ name: '5. 貪欲法', slugs: [
		'greedy', 'greedy-leave-better-elements', 'greedy-no-worsening-exchange',
		'greedy-find-good-evaluation', 'greedy-lexicographical-minimum',
	] },
	// 6. グラフ基礎（再帰の使い道。基礎→DFS→BFS→連結管理）
	{ name: '6. グラフ基礎', slugs: [
		'preparation-for-graph', 'dfs', 'bfs', 'union-find',
	] },
	// 7. 順序を保つデータ構造（log 構造。set 上位→heap 族）
	{ name: '7. 順序構造', slugs: [
		'ordered-set', 'priority-queue', 'priority-queue-greedy-speedup',
		'priority-queue-kth-smallest', 'priority-queue-find-next-pair',
	] },
	// 8. 型テクニック（小さい発想の型）
	{ name: '8. 型テク', slugs: [
		'stack-parenthesis', 'tech-fix-center-of-three', 'average-to-zerosum',
		'doubling', 'lis', 'monotonic-stack', 'interval-set',
		'potentialized-union-find', '45-degrees-rotation',
	] },
	// 9. 数え上げ（包除原理ファミリー：2集合→一般→応用）
	{ name: '9. 包除原理', slugs: [
		'exclusion-principle-2sets', 'exclusion-principle',
		'exclusion-principle-many-sets', 'exclusion-principle-divisors',
		'exclusion-principle-power-of-2', 'exclusion-principle-dp',
	] },
	// 10. 高度データ構造・DP発展
	{ name: '10. 高度構造・DP', slugs: [
		'digit-dp', 'segment-tree', 'binary-indexed-tree', 'trie',
		'rerooting-dp', 'stack-dp-speedup', 'normal-slope-trick',
	] },
	// 11. グラフ発展
	{ name: '11. グラフ発展', slugs: [
		'biconnected-components', 'two-edge-connected-component',
		'dag-path-cover', 'matrix-tree-theorem',
	] },
	// 12. フロー（最後の大陸：基本→最大流→マッチング→費用→高速化）
	{ name: '12. フロー', slugs: [
		'flow', 'flow-maxflow-mincut', 'flow-bipartite-matching',
		'flow-bipartite-stable-set-etc', 'flow-residual-graph',
		'min-cost-flow', 'flow-submodular-optimization', 'b-flow',
		'maxflow-speedup-via-mincut', 'min-cost-flow-speedup',
		'flow-min-cost-tension',
	] },
];

// Flat learning-order list, derived from the groups above (kept for orderIdx
// lookups and as the back-compat surface other code may rely on).
const NOVI_TOPIC_ORDER = NOVI_TOPIC_GROUPS.flatMap(g => g.slugs);

// slug -> group name, for rendering the visual group separators below.
const NOVI_SLUG_TO_GROUP = {};
for (const g of NOVI_TOPIC_GROUPS) {
	for (const s of g.slugs) NOVI_SLUG_TO_GROUP[s] = g.name;
}
const NOVI_OTHER_GROUP = 'その他';

function renderNoviSteps(novi) {
	const expired = !!window.__NOVI_COOKIE_EXPIRED;
	const banner = expired
		? '<div style="background:#3a0808;color:#ffaaaa;border:1px solid #aa3333;padding:4px 8px;margin-bottom:6px;font-size:var(--fs-sm)">⚠ COOKIE 期限切れ — <code style="color:#ffeeaa">~/tmp/cp-navisteps/auth_session</code> を更新してください</div>'
		: '';
	if (!novi || !novi.workbooks) {
		return '<div class="panel-inner" style="padding:24px 8px 6px">'+banner
			+'<div style="color:var(--dim);font-size:var(--fs-sm)">no data</div></div>';
	}
	// NoviSteps は 級 Q11(最易)→Q1 の上に 段 D1→D7(最難) が乗る体系（Q1 より D1 の方が難しい）。
	// 2026-08-10 バグ修正: 以前は GRADES が Q1〜Q7 のみだったため、D グレードのタスクは
	// `if (!cells[t.grade]) continue;` で全カウントから黙って落ちていた（Q への誤合流では
	// なく丸ごと欠落。gen-draft-data.py 側の gnum() 数値衝突バグとは別の失敗モード）。
	const GRADES = ['Q7','Q6','Q5','Q4','Q3','Q2','Q1','D1','D2','D3','D4','D5','D6','D7'];
	const COL = {
		ac:'var(--green)',
		ac_with_editorial:'var(--amber)',
		wa:'var(--red)',
		ns:'var(--bar-bg)',
	};
	const DONE = {ac:1, ac_with_editorial:1};

	const rows = [];
	let totalDone=0, totalQ=0, totalAcSelf=0, totalAcEd=0, totalWa=0;
	for (const slug of Object.keys(novi.workbooks)) {
		const wb = novi.workbooks[slug];
		const cells = {};
		for (const g of GRADES) cells[g] = {ac:0, ac_with_editorial:0, wa:0, ns:0, _total:0};
		for (const t of wb.tasks||[]) {
			if (!cells[t.grade]) continue;
			cells[t.grade][t.status] = (cells[t.grade][t.status]||0) + 1;
			cells[t.grade]._total += 1;
		}
		let done=0, total=0;
		for (const g of GRADES) {
			done += cells[g].ac + cells[g].ac_with_editorial;
			total += cells[g]._total;
		}
		if (total === 0) continue;
		totalDone += done;
		totalQ += total;
		for (const g of GRADES) {
			totalAcSelf += cells[g].ac;
			totalAcEd += cells[g].ac_with_editorial;
			totalWa += cells[g].wa;
		}
		rows.push({slug, title: wb.title, cells, done, total, group: NOVI_SLUG_TO_GROUP[slug] || NOVI_OTHER_GROUP});
	}
	// Sort by learning order (dependency-based; see vault [[Novisteps]] 2026-08-10)
	const orderIdx = (s) => {
		const i = NOVI_TOPIC_ORDER.indexOf(s);
		return i === -1 ? 999 : i;
	};
	rows.sort((a,b) => orderIdx(a.slug) - orderIdx(b.slug));

	const remaining = totalQ - totalDone;
	const userStr = novi.user ? ' · '+escHtml(novi.user) : '';
	let h = '<div class="panel-inner" style="padding:24px 8px 6px;gap:4px">';
	h += banner;
	// Header summary
	h += '<div style="display:flex;justify-content:space-between;align-items:baseline;border-bottom:0.5px solid var(--border);padding-bottom:3px">';
	h += '<div style="font-size:var(--fs-xs);color:var(--dim);letter-spacing:.08em">TOPIC × GRADE'+userStr+'</div>';
	h += '<div style="font-size:var(--fs-sm)">'
		+'<span style="color:var(--green)">'+totalAcSelf+'</span>'
		+'<span style="color:var(--muted)">/</span>'
		+'<span style="color:var(--amber)">'+totalAcEd+'</span>'
		+'<span style="color:var(--muted)">/</span>'
		+'<span style="color:var(--red)">'+totalWa+'</span>'
		+'<span style="color:var(--muted);margin:0 6px"> 完了 </span>'
		+'<span style="color:var(--text);font-weight:500">'+totalDone+'/'+totalQ+'</span>'
		+'<span style="color:var(--muted);margin:0 6px"> 残 </span>'
		+'<span style="color:var(--text);font-weight:500">'+remaining+'</span>'
		+'</div>';
	h += '</div>';

	// Body: split rows into 2 columns
	const colGrid = '90px repeat('+GRADES.length+',1fr) 48px';
	const headerHTML =
		'<div style="display:grid;grid-template-columns:'+colGrid+';gap:2px;font-size:var(--fs-2xs);color:var(--muted);padding:0 4px">'
		+'<div></div>'
		+ GRADES.map(g=>'<div style="text-align:center;letter-spacing:.05em">'+g+'</div>').join('')
		+'<div style="text-align:right">total</div>'
		+'</div>';

	// Small, single-line separator marking the start of a topic group (12族).
	// Kept minimal on purpose — this panel is density-first.
	const renderGroupHeader = (name) =>
		'<div style="font-size:var(--fs-2xs);color:var(--dim);letter-spacing:.04em;padding:2px 4px 1px;margin-top:3px;border-top:0.5px solid var(--border);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'
		+escHtml(name)+'</div>';

	const renderRow = (r) => {
		const isFullDone = r.done === r.total;
		let row = '<div style="display:grid;grid-template-columns:'+colGrid+';gap:2px;align-items:center;padding:1px 4px;'
			+(isFullDone?'opacity:.55':'')+'">';
		const title = (r.title||r.slug).slice(0,7);
		row += '<div style="font-size:var(--fs-2xs);color:var(--text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="'+escHtml(r.slug)+'">'+escHtml(title)+'</div>';
		for (const g of GRADES) {
			const c = r.cells[g];
			if (c._total === 0) {
				row += '<div style="height:14px;background:transparent"></div>';
				continue;
			}
			const segs = [];
			for (const k of ['ac','ac_with_editorial','wa','ns']) {
				if (c[k] > 0) segs.push({c:COL[k], pct:c[k]/c._total*100});
			}
			let inner = '';
			for (const s of segs) inner += '<div style="height:100%;width:'+s.pct.toFixed(1)+'%;background:'+s.c+'"></div>';
			const label = (c.ac+c.ac_with_editorial)+'/'+c._total;
			row += '<div style="position:relative;height:14px;background:var(--muted);display:flex;border-radius:1px;overflow:hidden" title="'+g+' '+label+'">'+inner
				+'<div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:9px;color:#dde;text-shadow:0 0 2px #000">'+label+'</div>'
				+'</div>';
		}
		const pct = r.total ? Math.round(r.done/r.total*100) : 0;
		row += '<div style="font-size:var(--fs-2xs);text-align:right;color:'+(isFullDone?'var(--green)':'var(--text)')+'">'+r.done+'/'+r.total+' <span style="color:var(--dim)">'+pct+'%</span></div>';
		row += '</div>';
		return row;
	};

	const half = Math.ceil(rows.length / 2);
	const left = rows.slice(0, half);
	const right = rows.slice(half);

	h += '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;flex:1;min-height:0;overflow:hidden">';
	for (const col of [left, right]) {
		h += '<div style="display:flex;flex-direction:column;min-height:0;overflow:hidden">';
		h += headerHTML;
		let lastGroup = null;
		for (const r of col) {
			if (r.group !== lastGroup) {
				h += renderGroupHeader(r.group);
				lastGroup = r.group;
			}
			h += renderRow(r);
		}
		h += '</div>';
	}
	h += '</div>';

	// Footer legend
	h += '<div style="display:flex;gap:10px;font-size:var(--fs-2xs);color:var(--dim);padding-top:2px;border-top:0.5px solid var(--border)">';
	h += '<span><span style="display:inline-block;width:8px;height:8px;background:var(--green);margin-right:2px"></span>AC</span>';
	h += '<span><span style="display:inline-block;width:8px;height:8px;background:var(--amber);margin-right:2px"></span>解説AC</span>';
	h += '<span><span style="display:inline-block;width:8px;height:8px;background:var(--red);margin-right:2px"></span>挑戦中</span>';
	h += '<span><span style="display:inline-block;width:8px;height:8px;background:var(--bar-bg);margin-right:2px"></span>未挑戦</span>';
	h += '</div>';

	h += '</div>';
	return h;
}
