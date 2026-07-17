// LAST SUB — 直近提出への反応領域（gen-inject が __RECENT_SUBS を注入）。
// 15分以内の提出は .fresh 発光＝「提出→盤面が反応した」の視覚的終点。
function renderLastSub() {
	const subs = window.__RECENT_SUBS || [];
	if (!subs.length) return '';
	const s = subs[subs.length - 1];
	const ageSec = Math.max(0, Date.now() / 1000 - (s.epoch || 0));
	const fresh = ageSec < 15 * 60;
	const ago = ageSec < 60 ? Math.floor(ageSec) + '秒前'
		: ageSec < 3600 ? Math.floor(ageSec / 60) + '分前'
		: ageSec < 86400 ? Math.floor(ageSec / 3600) + '時間前'
		: Math.floor(ageSec / 86400) + '日前';
	const ok = s.result === 'AC';
	const rc = ok ? 'var(--green)' : s.result === 'WA' ? 'var(--red)' : 'var(--amber)';
	return '<div class="hud-section'+(fresh ? ' hud-fresh' : '')+'"><div class="hud-label">last sub</div>'
		+'<div class="hud-value" style="font-size:var(--fs-md);color:'+rc+'">'+(s.result||'?')+' <span style="color:var(--text)">'+(s.problem_id||'')+'</span></div>'
		+'<div class="hud-sub"'+(fresh ? ' style="color:var(--green)"' : '')+'>'+ago+(fresh ? ' ⚡' : '')+'</div></div>';
}

function renderHUD(d) {
	const h = d.hud || {}, ps = d.player_status || {};
	const fc = (d.contests||[])[0];
	function s(l,v,sub,c) {
		return '<div class="hud-section"><div class="hud-label">'+l+'</div><div class="hud-value" style="color:'+c+'">'+v+'</div>'+(sub?'<div class="hud-sub">'+sub+'</div>':'')+'</div>';
	}
	const todayAc = (ps.today_acs||[]).length;
	const totalAc = h.ac_count || 0;

	// Next color band calculation using RPS efficiency
	const colorBands=[[400,'茶','#804000'],[800,'緑','#008000'],[1200,'水','#00c0c0'],[1600,'青','#0000ff'],[2000,'黄','#c0c000'],[2400,'橙','#ff8000'],[2800,'赤','#ff0000']];
	const curRating=ps.rating||0;
	let nextLabel='?',nextColor='#4a6a4a',targetR=400;
	for(let i=0;i<colorBands.length;i++){if(curRating<colorBands[i][0]){nextLabel=colorBands[i][1];nextColor=colorBands[i][2];targetR=colorBands[i][0];break;}}
	const remain=targetR-curRating;
	const dl=d.difficulty_log||{};
	const avgWkDiff=dl.avg_weekly_diff||0;
	const eff=dl.rps_efficiency||0.005;
	let nextEstimate='';
	if(avgWkDiff>0){
		const wkGain=avgWkDiff*eff;
		const weeks=Math.ceil(remain/wkGain);
		nextEstimate=weeks<=4?weeks+'週':Math.ceil(weeks/4)+'ヶ月';
		nextEstimate+=' (週'+avgWkDiff+'diff)';
	}else{
		nextEstimate='精進再開待ち';
	}

	return '<div class="hud" style="background:var(--dbg-hud)">'
		+s('user',(d.user||'---'),'','#1a5a2a')
		+s('rating',h.rating+' <span style="color:var(--dim)">'+(h.rank_label||'')+'</span>','','var(--amber)')
		+s('streak','🔥 '+(h.streak_days||0)+'日','','#ff8030')
		+s('today ac',todayAc+'問','total '+(totalAc),'var(--green)')
		+s('合計AC',totalAc+'問','','var(--cyan)')
		+s('初AC',h.first_ac_today||'--:--','avg '+(h.avg_first_ac||'--:--'),'#ffcc00')
		+s(nextLabel+'まで','+'+remain,nextEstimate,nextColor)
		+renderLastSub()
		+(fc?'<div class="hud-boss"><div><div style="font-size:var(--fs-2xs);color:#3a2a00;letter-spacing:.12em;text-transform:uppercase">BOSS FIGHT</div><div style="font-size:var(--fs-md);color:var(--amber);font-weight:500" id="boss-name">'+fc.type+' '+fc.id.replace(/[a-z]+/,'')+'</div></div><div class="hud-boss-timer" id="boss-timer">--:--:--</div></div>':'')
		+'</div>';
}

// P3 ヒーロー交換の定数: 外部締切（授業開始 = atcoder-cyan-perf の deadline）
const AMMO_DEADLINE = '2026-08-19';

// 残弾 = 締切までの土曜日の数（ABC はほぼ毎週土曜開催）
function _ammoCount() {
	const end = new Date(AMMO_DEADLINE + 'T23:59:59+09:00');
	let n = 0;
	const d = new Date();
	d.setHours(0, 0, 0, 0);
	for (; d <= end; d.setDate(d.getDate() + 1)) if (d.getDay() === 6) n++;
	return n;
}

// 直近 perf 自己比 = 最新 perf − 直近5回（最新を除く）の平均
function _perfSelfDelta(d) {
	const rh = (d.rating_history || []).filter(c => typeof c.performance === 'number');
	if (!rh.length) return null;
	const last = rh[rh.length - 1];
	const prev = rh.slice(-6, -1).map(c => c.performance);
	const base = prev.length ? Math.round(prev.reduce((a, b) => a + b, 0) / prev.length) : null;
	return { perf: last.performance, base, delta: base === null ? null : last.performance - base };
}

function renderPlayerStatus(d) {
	const ps = d.player_status||{}, h = d.hud||{};
	const pct = ((ps.rating_progress||0)*100).toFixed(1);
	const todayAc = (ps.today_acs||[]).length;
	const totalAc = h.ac_count || 0;
	const ammo = _ammoCount();
	const pd = _perfSelfDelta(d);
	const ammoColor = ammo <= 3 ? 'var(--red)' : ammo <= 5 ? 'var(--amber)' : 'var(--green)';
	let perfHtml = '<span style="color:var(--muted)">--</span>';
	if (pd) {
		const dc = pd.delta === null ? 'var(--muted)' : pd.delta >= 0 ? 'var(--green)' : 'var(--red)';
		const ds = pd.delta === null ? '' : ' <span style="font-size:var(--fs-lg);color:' + dc + '">' + (pd.delta >= 0 ? '▲+' : '▼') + pd.delta + '</span>';
		perfHtml = '<span class="ps-level" style="color:var(--cyan)">' + pd.perf + '</span>' + ds
			+ (pd.base !== null ? '<div style="font-size:var(--fs-xs);color:var(--dim)">自分の直近5回 avg ' + pd.base + '</div>' : '');
	}
	return '<div class="panel accent-amber" data-label="PLAYER STATUS" style="background:var(--dbg-player)"><div class="panel-inner">'
		+'<div style="display:flex;justify-content:space-between;align-items:flex-end"><div><div style="font-size:var(--fs-sm);color:#8aaa9a">残弾 · ABC〜8/19</div><div class="ps-rating" style="color:'+ammoColor+'">'+ammo+'</div></div><div style="text-align:right"><div style="font-size:var(--fs-sm);color:#8aaa9a">直近PERF vs 自分</div><div>'+perfHtml+'</div></div></div>'
		+'<div class="progress-bar"><div class="progress-fill" style="width:'+pct+'%;background:var(--amber)"></div></div>'
		+'<div style="display:flex;justify-content:space-between;font-size:var(--fs-sm);color:var(--muted)"><span>'+(ps.rating_min||0)+'</span><span style="color:var(--amber)">RATING '+(ps.rating||0)+' · AC '+totalAc+'</span><span style="color:var(--green)">'+(ps.rating_max||0)+'</span></div>'
		+'<div class="ps-box-green"><div style="font-size:var(--fs-sm);color:#3a8a5a">TODAY AC</div><div><span class="ps-xp">'+todayAc+'</span> <span style="font-size:var(--fs-sm);color:#1a5a1a">問</span></div></div>'
		+'<div style="flex:1 1 0;min-height:0;position:relative;overflow:hidden"><div style="position:absolute;inset:0;display:flex;align-items:stretch;justify-content:center">'+renderSkillGraph(d)+'</div></div>'
		+'<div class="ps-box-amber"><span style="font-size:var(--fs-lg)">🔥</span><div><span class="ps-streak">'+(ps.streak_days||0)+'</span> <span style="font-size:var(--fs-sm);color:#6a3a00">日連続</span><div style="font-size:var(--fs-sm);color:#5a3a00">最長: '+(ps.max_streak||0)+'日</div></div></div>'
		+'</div></div>';
}

const VOLUME_COLOR_MAP={灰:'#8a8a8a',茶:'#804000',緑:'#008000',水:'#00c0c0',青:'#0000ff',黄:'#c0c000',橙:'#ff8000',赤:'#ff0000'};
const VOLUME_COLOR_ORDER=['灰','茶','緑','水','青','黄','橙','赤'];

function _todayVolume(d){const days=(d.daily_volume&&d.daily_volume.days)||[];return days.length?days[days.length-1]:{};}

function renderTodayVolume(d){
	const t=_todayVolume(d);
	const bc=t.by_color||{};
	const total=VOLUME_COLOR_ORDER.reduce((a,c)=>a+(bc[c]||0),0);
	let bar='<div class="quality-bar" style="height:10px">';
	if(total>0){
		VOLUME_COLOR_ORDER.forEach(c=>{const n=bc[c]||0;if(!n)return;bar+='<div class="quality-seg" style="background:'+VOLUME_COLOR_MAP[c]+';opacity:.75;width:'+(n/total*100).toFixed(1)+'%" title="'+c+':'+n+'"></div>';});
	}else{bar+='<div class="quality-seg" style="background:var(--muted);width:100%;opacity:.3"></div>';}
	bar+='</div>';
	let chips='<div style="display:flex;gap:4px;flex-wrap:wrap;font-size:var(--fs-2xs)">';
	VOLUME_COLOR_ORDER.forEach(c=>{const n=bc[c]||0;if(!n)return;chips+='<span style="color:'+VOLUME_COLOR_MAP[c]+'">'+c+n+'</span>';});
	chips+='</div>';
	function cell(label,val,color){return '<div><div style="font-size:var(--fs-xs);color:var(--muted)">'+label+'</div><div style="font-size:var(--fs-lg);color:'+color+';line-height:1.1">'+val+'</div></div>';}
	// 週次デルタ: 直近7日 vs その前7日（自己参照の伸び実感）
	const days=(d.daily_volume&&d.daily_volume.days)||[];
	const wk=days.slice(-7), pw=days.slice(-14,-7);
	const sum=(a,k)=>a.reduce((x,y)=>x+Number(y[k]||0),0);
	function dcell(label,cur,prev){
		const diff=cur-prev;
		const c=diff>0?'var(--green)':diff<0?'var(--red)':'var(--muted)';
		const arrow=diff>0?'▲+':diff<0?'▼':'±';
		return '<div><div style="font-size:var(--fs-xs);color:var(--muted)">'+label+'</div>'
			+'<div style="font-size:var(--fs-md);line-height:1.1"><span style="color:var(--text)">'+cur+'</span> <span style="color:'+c+'">'+arrow+(diff===0?'0':Math.abs(diff))+'</span></div>'
			+'<div style="font-size:var(--fs-2xs);color:var(--dim)">先週 '+prev+'</div></div>';
	}
	const weekDelta='<div style="border-top:0.5px solid var(--border);padding-top:4px;margin-top:2px">'
		+'<div style="font-size:var(--fs-xs);color:var(--muted);letter-spacing:.1em;margin-bottom:2px">WEEK Δ（今週 vs 先週）</div>'
		+'<div style="display:grid;grid-template-columns:1fr 1fr;gap:4px 8px">'
		+dcell('AC',sum(wk,'count'),sum(pw,'count'))
		+dcell('SUM XP',sum(wk,'sum_xp'),sum(pw,'sum_xp'))
		+'</div></div>';
	return '<div class="panel" data-label="TODAY VOLUME"><div class="panel-inner" style="padding:28px 10px 8px">'
		+'<div style="display:grid;grid-template-columns:1fr 1fr;gap:6px 8px">'
		+cell('COUNT',(t.count||0)+'問','var(--green)')
		+cell('MAX DIFF',t.max_diff||0,'var(--cyan)')
		+cell('SUM XP',t.sum_xp||0,'var(--amber)')
		+cell('TOP3',t.top3_sum||0,'var(--cyan)')
		+'<div style="grid-column:1/3">'+cell('PERF Σ2^(d/400)',(t.perf||0).toFixed(1),'var(--green)')+'</div>'
		+'</div>'
		+bar
		+chips
		+weekDelta
		+'</div></div>';
}

function renderVolumeHistory(d,metric,label,color){
	const days=((d.daily_volume&&d.daily_volume.days)||[]).slice(-14);
	const vals=days.map(x=>Number(x[metric]||0));
	const max=Math.max(1,...vals);
	const today=vals.length?vals[vals.length-1]:0;
	const avg=vals.length?(vals.reduce((a,b)=>a+b,0)/vals.length):0;
	const fmt=v=>metric==='perf'?(Math.round(v*10)/10).toFixed(1):Math.round(v);
	const fmtShort=v=>{const n=Number(v);if(metric==='perf')return n.toFixed(1);if(n>=1000)return(n/1000).toFixed(n>=10000?0:1)+'k';return Math.round(n);};
	const streakDays=Math.max(0,Math.min(days.length,Number((d.hud||{}).streak_days||0)));
	// Display most-recent first (top → bottom)
	const ordered = days.map((x,i)=>({x, i, v:vals[i], isToday:i===days.length-1, inStreak:streakDays>0&&i>=days.length-streakDays})).reverse();
	let rows='<div style="flex:1;min-height:0;display:flex;flex-direction:column;gap:1px;overflow:hidden">';
	ordered.forEach(o=>{
		const w=o.v>0?Math.max(2,(o.v/max)*100):0;
		const op=o.isToday?1:(o.inStreak?.85:.45);
		const md=o.x.date.slice(5).replace('-','/');
		const dateColor=o.isToday?color:(o.inStreak?'var(--text)':'var(--dim)');
		rows+='<div style="display:flex;align-items:center;gap:3px;flex:1;min-height:0" title="'+o.x.date+': '+fmt(o.v)+'">'
			+'<div style="font-size:9px;color:'+dateColor+';width:24px;flex-shrink:0;line-height:1">'+md+'</div>'
			+'<div style="flex:1;height:80%;background:#0a1010;position:relative;min-width:0">'
				+(o.v>0?'<div style="height:100%;width:'+w.toFixed(1)+'%;background:'+color+';opacity:'+op+'"></div>':'')
			+'</div>'
			+'<div style="font-size:9px;color:'+(o.v>0?(o.isToday?color:'var(--text)'):'var(--muted)')+';width:24px;text-align:right;line-height:1;flex-shrink:0">'+(o.v>0?fmtShort(o.v):'')+'</div>'
		+'</div>';
	});
	rows+='</div>';
	return '<div class="panel" data-label="'+label+'" style="flex:1;min-height:0;overflow:hidden"><div class="panel-inner" style="padding:18px 6px 4px;gap:2px;height:100%">'
		+'<div style="display:flex;justify-content:space-between;align-items:baseline;flex-shrink:0">'
		+'<div style="font-size:var(--fs-lg);color:'+color+';line-height:1;font-weight:500">'+fmt(today)+'</div>'
		+'<div style="font-size:var(--fs-2xs);color:var(--muted)">avg '+fmt(avg)+'</div>'
		+'</div>'
		+rows
		+'</div></div>';
}

function renderContestList(d) {
	const days=['日','月','火','水','木','金','土'];
	let h='<div class="section-label">コンテスト</div>';
	(d.contests||[]).slice(0,5).forEach((c,i)=>{const dt=new Date(c.start_epoch*1000),ds=(dt.getMonth()+1)+'/'+dt.getDate()+' ('+days[dt.getDay()]+') '+String(dt.getHours()).padStart(2,'0')+':'+String(dt.getMinutes()).padStart(2,'0'),b=c.type==='ABC'?'contest-badge-abc':c.type==='ARC'?'contest-badge-arc':'contest-badge-ahc',r=c.is_rated_for_user?'<div class="contest-rated yes">'+c.rated_range+' ●</div>':'<div class="contest-rated">対象外</div>',t=c.title.replace(/.*\(/,'').replace(/\)$/,'').replace('AtCoder ','');
	h+='<div class="contest-item"><span class="contest-badge '+b+'">'+c.type+'</span><div style="flex:1;min-width:0"><div class="contest-name">'+t+'</div><div class="contest-time"'+(i===0?' style="color:var(--amber)"':'')+'>'+ds+(i===0?' BOSS':'')+'</div></div>'+r+'</div>';});
	return h;
}
