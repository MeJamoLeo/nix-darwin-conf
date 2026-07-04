const NOVI_TOPIC_ORDER = [
	// データ構造
	'bucket', 'set', 'map', 'interval-set', 'potentialized-union-find',
	'binary-indexed-tree', 'stack', 'queue', 'doubling',
	// 探索・シミュレーション・実装
	'recursive-function', 'bitmask-brute-force-search',
	'next-permutation-search', 'recursive-brute-force-search',
	// 動的計画法
	'digit-dp', 'lis',
	// グラフ
	'preparation-for-graph', 'dfs', 'bfs',
	'flow-bipartite-matching', 'flow-bipartite-stable-set-etc',
	'flow-connectivity-pathpacking', 'dag-path-cover',
	// 木
	'rerooting-dp',
	// 文字列
	'trie',
	// 数学（整数論）
	'number-theory-search', 'prime-divisor-factorization', 'eatosthenes',
	// 数え上げ・確率・期待値
	'exclusion-principle',
	// 最適化
	'greedy', 'greedy-find-good-evaluation', 'greedy-no-worsening-exchange',
	'greedy-leave-better-elements', 'greedy-lexicographical-minimum',
	// その他
	'tech-fix-center-of-three', '45-degrees-rotation',
];

function renderNoviSteps(novi) {
	const expired = !!window.__NOVI_COOKIE_EXPIRED;
	const banner = expired
		? '<div style="background:#3a0808;color:#ffaaaa;border:1px solid #aa3333;padding:4px 8px;margin-bottom:6px;font-size:var(--fs-sm)">⚠ COOKIE 期限切れ — <code style="color:#ffeeaa">~/tmp/cp-navisteps/auth_session</code> を更新してください</div>'
		: '';
	if (!novi || !novi.workbooks) {
		return '<div class="panel-inner" style="padding:24px 8px 6px">'+banner
			+'<div style="color:var(--dim);font-size:var(--fs-sm)">no data</div></div>';
	}
	const GRADES = ['Q7','Q6','Q5','Q4','Q3','Q2','Q1'];
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
		rows.push({slug, title: wb.title, cells, done, total});
	}
	// Sort by NoviSteps website display order (category-grouped)
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
	const colGrid = '90px repeat(7,1fr) 48px';
	const headerHTML =
		'<div style="display:grid;grid-template-columns:'+colGrid+';gap:2px;font-size:var(--fs-2xs);color:var(--muted);padding:0 4px">'
		+'<div></div>'
		+ GRADES.map(g=>'<div style="text-align:center;letter-spacing:.05em">'+g+'</div>').join('')
		+'<div style="text-align:right">total</div>'
		+'</div>';

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
		for (const r of col) h += renderRow(r);
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
