function renderDifficultyLog(d) {
	const dl=d.difficulty_log||{}, rh=d.rating_history||[], pts=dl.points||[];
	const proj=dl.projections||[], cr=dl.current_rating||0;
	if(!rh.length&&!pts.length) return '<div class="panel" data-label="DIFFICULTY LOG" style="background:var(--dbg-difflog)"><div class="panel-inner"></div></div>';

	const WEEK=7*86400;
	const dataStart=pts.length?pts[0].epoch:(rh.length?rh[0].epoch:0);
	const frh=rh.filter(r=>r.epoch>=dataStart-30*86400);

	const allEpochs=[];
	frh.forEach(r=>allEpochs.push(r.epoch));
	pts.forEach(p=>allEpochs.push(p.epoch));
	proj.forEach(pr=>pr.points.forEach(p=>allEpochs.push(p.epoch)));
	if(!allEpochs.length) return '<div class="panel" data-label="DIFFICULTY LOG" style="background:var(--dbg-difflog)"><div class="panel-inner"></div></div>';
	const mE=Math.min(...allEpochs),xE=Math.max(...allEpochs);
	const totalWeeks=Math.ceil((xE-mE)/WEEK)+1;

	const weekDiff={};
	pts.forEach(p=>{const wk=Math.floor((p.epoch-mE)/WEEK);weekDiff[wk]=(weekDiff[wk]||0)+p.difficulty;});

	const weekRate={};
	frh.forEach(r=>{const wk=Math.floor((r.epoch-mE)/WEEK);weekRate[wk]=r;});

	const W=560,H=510,xL=44,xR=550,yT=30,yB=435;
	const colW=(xR-xL)/totalWeeks;
	const Xw=wk=>xL+(wk+0.5)*colW;

	const bandThresholds=[0,400,800,1200,1600,2000,2400,2800,3200];
	let curBandIdx=0;for(let i=bandThresholds.length-1;i>=0;i--){if(cr>=bandThresholds[i]){curBandIdx=i;break;}}
	const targetIdx=Math.min(curBandIdx+3,bandThresholds.length-1);
	const maxR=bandThresholds[targetIdx];
	const YR=v=>yB-(v/maxR)*(yB-yT);

	const diffVals=Object.values(weekDiff);
	const maxSum=diffVals.length?Math.max(...diffVals):1;
	const YS=v=>yB-(v/maxSum)*(yB-yT)*0.6;

	const nowEpoch=frh.length?frh[frh.length-1].epoch:(pts.length?pts[pts.length-1].epoch:mE);
	const nowWk=Math.floor((nowEpoch-mE)/WEEK);

	let s='<svg width="100%" height="100%" viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg">';

	const bands=[[0,'#808080'],[400,'#804000'],[800,'#008000'],[1200,'#00c0c0'],[1600,'#0000ff'],[2000,'#c0c000'],[2400,'#ff8000'],[2800,'#ff0000']];
	for(let i=0;i<bands.length;i++){const lo=bands[i][0],hi=i+1<bands.length?bands[i+1][0]:maxR,col=bands[i][1];if(hi<=0||lo>=maxR)continue;const y1=YR(Math.min(hi,maxR)),y2=YR(Math.max(lo,0));if(y2<=yT||y1>=yB)continue;const cy1=Math.max(y1,yT),cy2=Math.min(y2,yB);s+='<rect x="'+xL+'" y="'+cy1.toFixed(1)+'" width="'+(xR-xL)+'" height="'+(cy2-cy1).toFixed(1)+'" fill="'+col+'" opacity="0.06"/>';}

	const futX=xL+(nowWk+1)*colW;
	s+='<rect x="'+futX.toFixed(1)+'" y="'+yT+'" width="'+(xR-futX).toFixed(1)+'" height="'+(yB-yT)+'" fill="#020404" opacity="0.5"/>';

	for(let v=200;v<maxR;v+=200){const y=YR(v);s+='<line x1="'+xL+'" y1="'+y+'" x2="'+xR+'" y2="'+y+'" stroke="#0c1c1c" stroke-width="0.5"/><text x="38" y="'+(y+2)+'" fill="#1a2a2a" font-size="7" text-anchor="end" font-family="monospace">'+v+'</text>';}

	if(cr>0){const y=YR(cr),rc=ratingColor(cr);s+='<line x1="'+xL+'" y1="'+y+'" x2="'+xR+'" y2="'+y+'" stroke="'+rc+'" stroke-width="0.5" stroke-dasharray="3,3" opacity="0.5"/><text x="38" y="'+(y+3)+'" fill="'+rc+'" font-size="8" text-anchor="end" font-family="monospace" font-weight="bold">'+cr+'</text>';}

	s+='<line x1="'+Xw(nowWk).toFixed(1)+'" y1="'+yT+'" x2="'+Xw(nowWk).toFixed(1)+'" y2="'+yB+'" stroke="var(--dim)" stroke-width="0.5" stroke-dasharray="2,3"/>';

	const barW=colW*0.8;
	Object.entries(weekDiff).forEach(([wk,sum])=>{wk=Number(wk);const x=Xw(wk),y=YS(sum),h=yB-y;s+='<rect x="'+(x-barW/2).toFixed(1)+'" y="'+y.toFixed(1)+'" width="'+barW.toFixed(1)+'" height="'+h.toFixed(1)+'" fill="#1a5a3a" opacity="0.55" rx="1"/>';});

	const projColorMap={optimistic:'var(--green)',maintain:'var(--amber)',pessimistic:'var(--dim)'};
	const effortMap=proj.map(pr=>{const last=pr.points.length?pr.points[pr.points.length-1]:{rating:0};return{weeklyDiff:pr.weekly_diff||0,endRating:last.rating||0,color:projColorMap[pr.scenario]||'var(--dim)'};});

	const todayWk=Math.floor((Date.now()/1000-mE)/WEEK);
	effortMap.forEach(t=>{if(!t.weeklyDiff||!t.endRating)return;const y=YS(t.weeklyDiff),h=yB-y,x=Xw(todayWk),prc=ratingColor(t.endRating);const daily=Math.round(t.weeklyDiff/7);s+='<rect x="'+(x-barW/2).toFixed(1)+'" y="'+y.toFixed(1)+'" width="'+barW.toFixed(1)+'" height="'+h.toFixed(1)+'" fill="'+t.color+'" opacity="0.08" rx="1"/>';s+='<line x1="'+(x-barW/2).toFixed(1)+'" y1="'+y.toFixed(1)+'" x2="'+(x+barW/2).toFixed(1)+'" y2="'+y.toFixed(1)+'" stroke="'+t.color+'" stroke-width="0.8" stroke-dasharray="3,2" opacity="0.5"/>';s+='<text x="'+(x+barW/2+3).toFixed(1)+'" y="'+(y+3).toFixed(1)+'" fill="'+t.color+'" font-size="6" font-family="monospace" opacity="0.7">日'+daily+' → <tspan fill="'+prc+'">'+t.endRating+'</tspan></text>';});

	const rWeeks=Object.keys(weekRate).map(Number).sort((a,b)=>a-b);
	if(rWeeks.length>1){
		s+='<polyline points="'+rWeeks.map(wk=>Xw(wk).toFixed(1)+','+YR(weekRate[wk].new_rating).toFixed(1)).join(' ')+'" fill="none" stroke="var(--amber)" stroke-width="1.5" stroke-linejoin="round"/>';
	}
	rWeeks.forEach((wk,i)=>{const r=weekRate[wk],delta=r.new_rating-r.old_rating,col=delta>=0?'var(--green)':'var(--red)',rc=ratingColor(r.new_rating);const cx=Xw(wk).toFixed(1),cy=YR(r.new_rating).toFixed(1);s+='<circle cx="'+cx+'" cy="'+cy+'" r="2.5" fill="'+rc+'" stroke="'+rc+'" stroke-width="0.5" opacity="0.9"/>';const sign=delta>=0?'+':'';s+='<text x="'+cx+'" y="'+(YR(r.new_rating)-8).toFixed(1)+'" fill="'+col+'" font-size="6" text-anchor="middle" font-family="monospace">'+sign+delta+'</text>';s+='<text x="'+cx+'" y="'+(YR(r.new_rating)+10).toFixed(1)+'" fill="'+rc+'" font-size="6" text-anchor="middle" font-family="monospace" opacity="0.9">'+r.new_rating+'</text>';});

	proj.forEach(pr=>{const col=projColorMap[pr.scenario]||'#555';if(!frh.length||!pr.points.length)return;const lastR=frh[frh.length-1];let polyPts=Xw(nowWk).toFixed(1)+','+YR(lastR.new_rating).toFixed(1);pr.points.forEach(p=>{const wk=Math.floor((p.epoch-mE)/WEEK);polyPts+=' '+Xw(wk).toFixed(1)+','+YR(p.rating).toFixed(1);});s+='<polyline points="'+polyPts+'" fill="none" stroke="'+col+'" stroke-width="1" stroke-dasharray="4,3" opacity="0.7"/>';const last=pr.points[pr.points.length-1],lwk=Math.floor((last.epoch-mE)/WEEK),prc=ratingColor(last.rating);const em=effortMap.find(e=>e.endRating===last.rating);const label=em?'週'+em.weeklyDiff+' → '+last.rating:''+last.rating;s+='<text x="'+(Xw(lwk)+4).toFixed(1)+'" y="'+(YR(last.rating)+3).toFixed(1)+'" fill="'+prc+'" font-size="6" font-family="monospace">'+label+'</text>';});

	// ── 読める成長ヘッダー（YouTube Analytics 流：今どこ・どこへ）──
	const nextR = dl.next_color_rating || 0;
	const mtn = dl.months_to_next;
	const lastRh = rh.length ? rh[rh.length - 1] : null;
	const lastDelta = lastRh ? (lastRh.new_rating - lastRh.old_rating) : null;
	const colorLabelOf = r => { const B = [[400,'茶'],[800,'緑'],[1200,'水'],[1600,'青'],[2000,'黄'],[2400,'橙'],[2800,'赤']]; for (const [t,l] of B) { if (r <= t) return l; } return '?'; };
	const dc = lastDelta === null ? 'var(--muted)' : lastDelta >= 0 ? 'var(--green)' : 'var(--red)';
	const deltaHtml = lastDelta === null ? '' : '<span style="font-size:var(--fs-lg);color:' + dc + '">' + (lastDelta >= 0 ? '▲+' : '▼') + lastDelta + '</span> <span style="font-size:var(--fs-2xs);color:var(--muted)">直近</span>';
	const nextLabel = nextR ? colorLabelOf(nextR) : '';
	const paceHtml = (nextR && mtn != null)
		? nextLabel + '(' + nextR + ')まで 現ペース <span style="color:var(--text)">約' + (Math.round(mtn * 10) / 10) + 'ヶ月</span>'
		: '精進再開待ち';
	const rc0 = cr > 0 ? ratingColor(cr) : 'var(--amber)';
	const headerHtml =
		'<div style="display:flex;align-items:baseline;gap:10px;padding:0 4px 3px;flex-shrink:0">'
		+ '<span style="font-size:var(--fs-2xs);color:#8aaa9a">RATING</span>'
		+ '<span style="font-size:var(--fs-xl);font-weight:500;color:' + rc0 + ';line-height:1">' + cr + '</span>'
		+ deltaHtml
		+ '<span style="flex:1"></span>'
		+ '<span style="font-size:var(--fs-2xs);color:var(--dim)">' + paceHtml + '</span>'
		+ '</div>'
		+ '<div style="display:flex;gap:12px;padding:0 4px 4px;font-size:var(--fs-2xs);color:var(--muted);flex-shrink:0;border-bottom:0.5px solid var(--border)">'
		+ '<span><span style="color:var(--amber)">━</span> あなたの推移</span>'
		+ '<span><span style="color:var(--green)">┄</span> 努力別の到達予想</span>'
		+ '<span><span style="color:#1a5a3a">▮</span> 週の演習量</span>'
		+ '</div>';

	function fmtDate(ep){const d=new Date(ep*1000);return(d.getMonth()+1)+'/'+d.getDate();}
	const labelY=yB+15;
	s+='<text x="'+xL+'" y="'+labelY+'" fill="#1a2a2a" font-size="7" text-anchor="start" font-family="monospace">'+fmtDate(mE)+'</text>';
	const todayEp=Math.floor(Date.now()/1000);
	s+='<line x1="'+Xw(todayWk).toFixed(1)+'" y1="'+yT+'" x2="'+Xw(todayWk).toFixed(1)+'" y2="'+yB+'" stroke="var(--cyan)" stroke-width="0.5" stroke-dasharray="2,3" opacity="0.4"/>';
	s+='<text x="'+Xw(todayWk).toFixed(1)+'" y="'+labelY+'" fill="var(--cyan)" font-size="7" text-anchor="middle" font-family="monospace">'+fmtDate(todayEp)+'</text>';
	s+='<text x="'+xR+'" y="'+labelY+'" fill="var(--dim)" font-size="7" text-anchor="end" font-family="monospace">'+fmtDate(xE)+'</text>';
	s+='</svg>';

	return '<div class="panel" data-label="RATING 成長" style="background:var(--dbg-difflog)"><div class="panel-inner">'
		+headerHtml
		+'<div style="flex:1;min-height:0">'+s+'</div></div></div>';
}
