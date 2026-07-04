// Cumulative NoviSteps AC trend with linear extrapolation to Q-grade milestones.
// Y = cumulative AC count (status ∈ {ac, ac_with_editorial}); is_ac=true covers both.
// Pace = 7-day rolling rate from "now" backward. Pace=0 → no projection, ETA "—".
// Goals = cumulative problem counts through grade Qk (k=7..1 in practice; Q10..Q8 vacuous).
// "Done" detection uses literal grade-set match: AC count of problems whose grade ∈ goal_set
// equals total problems in that set.

const NOVI_Q_ORDER = ['Q10','Q9','Q8','Q7','Q6','Q5','Q4','Q3','Q2','Q1'];

const NOVI_Q_COLOR = {
	Q10:'#888888', Q9:'#888888', Q8:'#888888',
	Q7:'#a07050', Q6:'#a07050',
	Q5:'#5aa07a', Q4:'#5aa07a',
	Q3:'#5ab0c0', Q2:'#5a8add',
	Q1:'#c0c050',
};

function renderNoviTrend(novi) {
	if (!novi || !novi.workbooks) {
		return '<div class="panel-inner" style="padding:24px 8px 6px;color:var(--dim);font-size:var(--fs-sm)">no data</div>';
	}

	const allAc = [];
	const gradeTotal = {};
	const gradeAc = {};
	for (const wb of Object.values(novi.workbooks)) {
		for (const t of (wb.tasks || [])) {
			gradeTotal[t.grade] = (gradeTotal[t.grade] || 0) + 1;
			if (t.is_ac) {
				gradeAc[t.grade] = (gradeAc[t.grade] || 0) + 1;
				allAc.push({ts: t.updated_at, grade: t.grade});
			}
		}
	}
	allAc.sort((a,b) => a.ts - b.ts);
	if (!allAc.length) {
		return '<div class="panel-inner" style="padding:24px 8px 6px;color:var(--dim);font-size:var(--fs-sm)">no AC yet</div>';
	}

	const now = Date.now();
	const DAY = 86400000;
	const firstTs = allAc[0].ts;
	const currentN = allAc.length;

	// 7-day pace (problems/day). Pace=0 → no projection.
	const windowStart = now - 7 * DAY;
	const recent = allAc.filter(a => a.ts >= windowStart).length;
	const pace = recent / 7;

	// Q-grade goals: cumulative through Q_k where Q_k exists in the workbook data.
	// Q10..Q8 are vacuously trivial (no problems) and skipped from rendering.
	const goals = [];
	let cumTotal = 0;
	const setGrades = [];
	for (const g of NOVI_Q_ORDER) {
		const n = gradeTotal[g] || 0;
		if (n === 0) continue;
		cumTotal += n;
		setGrades.push(g);
		const setAc = setGrades.reduce((s,gg) => s + (gradeAc[gg] || 0), 0);
		const setTotalAll = setGrades.reduce((s,gg) => s + (gradeTotal[gg] || 0), 0);
		const done = setAc >= setTotalAll;
		const remain = Math.max(0, cumTotal - currentN);
		const projDays = (pace > 0 && remain > 0) ? remain / pace : null;
		const projTs = projDays !== null ? now + projDays * DAY : null;
		goals.push({
			grade: g,
			total: cumTotal,
			setAc, setTotalAll,
			done,
			remain,
			projDays,
			projTs,
		});
	}

	// X-range: first AC to today + 90 days.
	const xMin = firstTs;
	const xMax = now + 90 * DAY;
	// Y-range: enough to show today's value + ~90-day projection with headroom.
	// Goals beyond yMax appear as upper-edge tags.
	const projAt90 = pace > 0 ? currentN + pace * 90 : currentN;
	const yMax = Math.max(currentN * 1.1, projAt90 * 1.1, 10);

	const W = 360, H = 200;
	const padL = 30, padR = 8, padT = 8, padB = 20;
	const plotW = W - padL - padR;
	const plotH = H - padT - padB;
	const X = ts => padL + ((ts - xMin) / (xMax - xMin)) * plotW;
	const Y = n  => padT + plotH - (n / yMax) * plotH;

	let svg = '<svg width="100%" height="100%" viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg" style="font-family:monospace">';

	// Plot border
	svg += '<rect x="'+padL+'" y="'+padT+'" width="'+plotW+'" height="'+plotH+'" fill="none" stroke="var(--border)" stroke-width="0.5"/>';

	// Y-axis ticks
	const yTickN = 4;
	for (let i = 0; i <= yTickN; i++) {
		const v = Math.round(yMax * i / yTickN);
		const y = Y(v);
		svg += '<line x1="'+(padL-2)+'" y1="'+y.toFixed(1)+'" x2="'+padL+'" y2="'+y.toFixed(1)+'" stroke="var(--muted)" stroke-width="0.5"/>';
		svg += '<text x="'+(padL-3)+'" y="'+(y+3).toFixed(1)+'" fill="var(--muted)" font-size="8" text-anchor="end">'+v+'</text>';
	}

	// X-axis: month markers
	const startD = new Date(xMin), endD = new Date(xMax);
	for (let y=startD.getFullYear(); y<=endD.getFullYear(); y++) {
		for (let m=0; m<12; m++) {
			const tickTs = new Date(y, m, 1).getTime();
			if (tickTs < xMin || tickTs > xMax) continue;
			const x = X(tickTs);
			svg += '<line x1="'+x.toFixed(1)+'" y1="'+(padT+plotH)+'" x2="'+x.toFixed(1)+'" y2="'+(padT+plotH+2)+'" stroke="var(--muted)" stroke-width="0.5"/>';
			svg += '<text x="'+x.toFixed(1)+'" y="'+(padT+plotH+10)+'" fill="var(--muted)" font-size="8" text-anchor="middle">'+(m+1)+'/'+String(y).slice(2)+'</text>';
		}
	}

	// "Today" vertical marker
	const xNow = X(now);
	svg += '<line x1="'+xNow.toFixed(1)+'" y1="'+padT+'" x2="'+xNow.toFixed(1)+'" y2="'+(padT+plotH)+'" stroke="var(--cyan)" stroke-width="0.5" stroke-dasharray="1,2" opacity="0.6"/>';

	// Goal horizontal lines (in-range only); out-of-range get upper-edge tags
	const yTagPositions = [];
	for (const g of goals) {
		const color = g.done ? 'var(--dim)' : (NOVI_Q_COLOR[g.grade] || 'var(--text)');
		if (g.total <= yMax) {
			const gy = Y(g.total);
			svg += '<line x1="'+padL+'" y1="'+gy.toFixed(1)+'" x2="'+(padL+plotW)+'" y2="'+gy.toFixed(1)+'" stroke="'+color+'" stroke-width="0.5" stroke-dasharray="3,3" opacity="'+(g.done?0.35:0.55)+'"/>';
			svg += '<text x="'+(padL+plotW-2)+'" y="'+(gy-2).toFixed(1)+'" fill="'+color+'" font-size="8" text-anchor="end" opacity="'+(g.done?0.5:0.85)+'">'+g.grade+(g.done?' ✓':'')+'</text>';
		} else {
			yTagPositions.push({grade: g.grade, color});
		}
	}
	// Out-of-range goal tags along top edge
	yTagPositions.forEach((t, i) => {
		const x = padL + plotW - 4 - i*22;
		svg += '<text x="'+x.toFixed(1)+'" y="'+(padT+8)+'" fill="'+t.color+'" font-size="8" text-anchor="end" opacity="0.85">↑'+t.grade+'</text>';
	});

	// Actual cumulative line (green solid)
	let path = '';
	allAc.forEach((a, i) => {
		path += (i ? ' L' : 'M') + X(a.ts).toFixed(1) + ',' + Y(i+1).toFixed(1);
	});
	// Extend horizontally from last AC to "now" so the actual line ends at today
	path += ' L' + xNow.toFixed(1) + ',' + Y(currentN).toFixed(1);
	svg += '<path d="'+path+'" fill="none" stroke="var(--green)" stroke-width="1.4" opacity="0.95"/>';

	// Projection line (amber dashed) — from today to today+90d
	if (pace > 0) {
		const px2 = X(xMax), py2 = Y(Math.min(yMax, projAt90));
		svg += '<line x1="'+xNow.toFixed(1)+'" y1="'+Y(currentN).toFixed(1)+'" x2="'+px2.toFixed(1)+'" y2="'+py2.toFixed(1)+'" stroke="var(--amber)" stroke-width="1.2" stroke-dasharray="3,2" opacity="0.85"/>';
	}

	// Goal × projection intersection dots (for in-chart goals reached within 90d window)
	for (const g of goals) {
		if (g.done || !g.projTs || g.projTs > xMax || g.total > yMax) continue;
		const gx = X(g.projTs), gy = Y(g.total);
		const color = NOVI_Q_COLOR[g.grade] || 'var(--amber)';
		svg += '<circle cx="'+gx.toFixed(1)+'" cy="'+gy.toFixed(1)+'" r="2.2" fill="'+color+'"/>';
	}

	svg += '</svg>';

	// ETA table on the right
	function fmtEta(days) {
		if (days < 14) return '+'+Math.ceil(days)+'日';
		if (days < 90) return '+'+Math.ceil(days/7)+'週';
		return '+'+(days/30.4).toFixed(1)+'ヶ月';
	}
	function fmtDate(ts) {
		const d = new Date(ts);
		return d.getFullYear() + '/' + String(d.getMonth()+1).padStart(2,'0');
	}

	let table = '<div style="display:flex;flex-direction:column;gap:1px;font-size:var(--fs-2xs);min-width:0">';
	table += '<div style="display:grid;grid-template-columns:24px 1fr 44px 40px;gap:4px;color:var(--muted);padding:0 2px 2px;border-bottom:0.5px solid var(--border)">'
		+'<span>G</span><span style="text-align:right">残</span><span style="text-align:right">ETA</span><span style="text-align:right">date</span></div>';
	for (const g of goals) {
		const color = g.done ? 'var(--dim)' : (NOVI_Q_COLOR[g.grade] || 'var(--text)');
		const eta = g.done ? '✓' : (g.projDays === null ? '—' : fmtEta(g.projDays));
		const dateStr = g.done ? '—' : (g.projTs === null ? '—' : fmtDate(g.projTs));
		const remainStr = g.done ? '—' : g.remain;
		table += '<div style="display:grid;grid-template-columns:24px 1fr 44px 40px;gap:4px;padding:1px 2px;color:'+color+';opacity:'+(g.done?0.55:1)+'">'
			+'<span>'+g.grade+'</span>'
			+'<span style="text-align:right">'+remainStr+'</span>'
			+'<span style="text-align:right">'+eta+'</span>'
			+'<span style="text-align:right">'+dateStr+'</span>'
			+'</div>';
	}
	table += '<div style="margin-top:auto;padding:2px;font-size:var(--fs-2xs);color:var(--dim);border-top:0.5px solid var(--border)">pace '+pace.toFixed(2)+'/d · 7d</div>';
	table += '</div>';

	// ── 読める成長ヘッダー（RATING 成長 と対の作り）──
	const nextGoal = goals.find(g => !g.done);
	const paceColor = pace > 0 ? 'var(--green)' : 'var(--muted)';
	const nextHtml = nextGoal
		? '次 <span style="color:' + (NOVI_Q_COLOR[nextGoal.grade] || 'var(--text)') + '">' + nextGoal.grade + '</span> まで 残' + nextGoal.remain + (nextGoal.projDays != null ? ' <span style="color:var(--text)">' + fmtEta(nextGoal.projDays) + '</span>' : ' <span style="color:var(--muted)">ETA—</span>')
		: '全 Q 到達 ✓';
	const headerHtml =
		'<div style="display:flex;align-items:baseline;gap:10px;padding:0 4px 3px;flex-shrink:0">'
		+ '<span style="font-size:var(--fs-2xs);color:#8aaa9a">NOVI AC</span>'
		+ '<span style="font-size:var(--fs-xl);font-weight:500;color:var(--green);line-height:1">' + currentN + '</span>'
		+ '<span style="font-size:var(--fs-sm);color:' + paceColor + '">ペース ' + pace.toFixed(2) + '/日</span>'
		+ '<span style="flex:1"></span>'
		+ '<span style="font-size:var(--fs-2xs);color:var(--dim)">' + nextHtml + '</span>'
		+ '</div>'
		+ '<div style="display:flex;gap:12px;padding:0 4px 4px;font-size:var(--fs-2xs);color:var(--muted);flex-shrink:0;border-bottom:0.5px solid var(--border)">'
		+ '<span><span style="color:var(--green)">━</span> 実績(累積AC)</span>'
		+ '<span><span style="color:var(--amber)">┄</span> 現ペース予測</span>'
		+ '<span><span style="color:var(--dim)">┈</span> 級ライン</span>'
		+ '</div>';
	return '<div class="panel-inner" style="padding:24px 6px 6px;gap:4px">'
		+ headerHtml
		+ '<div style="flex:1;min-height:0;display:flex;flex-direction:row;gap:8px">'
		+ '<div style="flex:1;min-width:0;display:flex;align-items:stretch">' + svg + '</div>'
		+ '<div style="width:128px;display:flex;flex-direction:column;min-height:0">' + table + '</div>'
		+ '</div>'
		+ '</div>';
}
