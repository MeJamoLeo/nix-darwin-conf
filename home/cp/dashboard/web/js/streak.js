function renderStreakCalendar(d) {
	const cal=d.streak_calendar||[], h=d.hud||{};
	const pts=(d.difficulty_log||{}).points||[];

	// Time-scatter: X=日付(10日), Y=時刻(5:00top→4:59bottom), dots=AC
	const SPAN=10;
	// Use local timezone offset instead of hardcoded JST
	const TZ_OFFSET=-(new Date().getTimezoneOffset())*60; // seconds
	const nowEp=Math.floor(Date.now()/1000);
	const startEp=nowEp-SPAN*86400;

	const recent=pts.filter(p=>p.epoch>=startEp);

	const dots=recent.map(p=>{
		const jst=new Date((p.epoch+TZ_OFFSET)*1000);
		const h=jst.getHours(),m=jst.getMinutes();
		const dayBoundary=h<5?-1:0;
		const jstDate=new Date((p.epoch+TZ_OFFSET+dayBoundary*86400)*1000);
		const dayIdx=Math.floor((p.epoch-startEp)/86400)+dayBoundary;
		const hourOff=((h-5+24)%24)+m/60;
		return{day:Math.max(0,Math.min(SPAN-1,dayIdx)),hour:hourOff,diff:p.difficulty};
	});

	const W=220,H=180,xL=24,xR=210,yT=8,yB=160;
	const colW=(xR-xL)/SPAN;
	const X=day=>xL+(day+0.5)*colW;
	const Y=hourOff=>yT+(hourOff/23)*(yB-yT);

	let s='<svg width="100%" height="100%" viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg">';

	[5,8,12,18,0].forEach(hr=>{const off=((hr-5+24)%24),y=Y(off);const label=String(hr).padStart(2,'0')+':00';s+='<text x="'+(xL-2)+'" y="'+(y+2)+'" fill="#1a2a2a" font-size="6" text-anchor="end" font-family="monospace">'+label+'</text>';s+='<line x1="'+xL+'" y1="'+y+'" x2="'+xR+'" y2="'+y+'" stroke="#0c1c1c" stroke-width="0.3"/>';});

	s+='<line x1="'+xL+'" y1="'+yT+'" x2="'+xR+'" y2="'+yT+'" stroke="#5a4000" stroke-width="0.5" stroke-dasharray="2,2" opacity="0.6"/>';

	for(let i=0;i<SPAN;i++){
		const ep=startEp+(i+1)*86400;
		const dt=new Date((ep+TZ_OFFSET)*1000);
		const label=(dt.getMonth()+1)+'/'+dt.getDate();
		s+='<line x1="'+X(i).toFixed(1)+'" y1="'+yT+'" x2="'+X(i).toFixed(1)+'" y2="'+yB+'" stroke="#0c1c1c" stroke-width="0.5"/>';
		s+='<text x="'+X(i)+'" y="'+(yB+10)+'" fill="#1a2a2a" font-size="5" text-anchor="middle" font-family="monospace">'+label+'</text>';
	}

	// Dots with known difficulty
	dots.forEach(p=>{const cx=X(p.day),cy=Y(p.hour),col=ratingColor(p.diff);s+='<circle cx="'+cx.toFixed(1)+'" cy="'+cy.toFixed(1)+'" r="3" fill="'+col+'" opacity="0.85"/>';});

	// White outline dots for days with AC in streak but no dots in scatter
	const dotDays=new Set();dots.forEach(p=>dotDays.add(p.day));
	cal.forEach(c=>{if(c.ac_count===0)return;const dt=new Date(c.date+'T12:00:00');const ep=Math.floor(dt.getTime()/1000);const dayIdx=Math.floor((ep-startEp)/86400);if(dayIdx<0||dayIdx>=SPAN)return;if(dotDays.has(dayIdx))return;const cx=X(dayIdx),cy=Y(7);s+='<circle cx="'+cx.toFixed(1)+'" cy="'+cy.toFixed(1)+'" r="3" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1" opacity="0.8"/>';});

	const earlyY1=Y(0),earlyY2=Y(3);
	s+='<rect x="'+xL+'" y="'+earlyY1+'" width="'+(xR-xL)+'" height="'+(earlyY2-earlyY1)+'" fill="#5a4000" opacity="0.04"/>';

	const dayHasAc={},dayHasEarly={};
	dots.forEach(p=>{dayHasAc[p.day]=true;if(p.hour<3)dayHasEarly[p.day]=true;});
	const acDays=Object.keys(dayHasAc).length;
	const earlyDays=Object.keys(dayHasEarly).length;
	const earlyPct=acDays>0?Math.round(earlyDays/acDays*100):0;

	s+='</svg>';

	// GitHub-style streak grid
	const now2=new Date(),ts2=now2.getFullYear()+'-'+String(now2.getMonth()+1).padStart(2,'0')+'-'+String(now2.getDate()).padStart(2,'0');
	const firstDow=cal.length?new Date(cal[0].date+'T00:00:00').getDay():0;
	let g='';
	for(let i=0;i<firstDow;i++)g+='<div class="streak-cell" style="opacity:0"></div>';
	cal.forEach(c=>{const today=c.date===ts2?' streak-today':'';if(c.ac_count===0){g+='<div class="streak-cell streak-none'+today+'"></div>';}else if(c.max_difficulty>0){g+='<div class="streak-cell'+today+'" style="background:'+ratingColor(c.max_difficulty)+';opacity:0.9"></div>';}else{g+='<div class="streak-cell'+today+'" style="background:rgba(255,255,255,0.25)"></div>';}});
	const totalCells=firstDow+cal.length;
	const remainder=totalCells%7;
	if(remainder>0)for(let i=0;i<7-remainder;i++)g+='<div class="streak-cell" style="opacity:0"></div>';

	const dayLabels='<div style="display:grid;grid-template-rows:repeat(7,1fr);gap:2px;font-size:var(--fs-2xs);color:var(--muted);text-align:right;padding-right:3px"><span>S</span><span>M</span><span>T</span><span>W</span><span>T</span><span>F</span><span>S</span></div>';

	return '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:3px"><span style="font-size:var(--fs-sm);color:var(--dim)">最長 '+(h.max_streak||0)+'日</span><span class="badge badge-amber">🔥 '+(h.streak_days||0)+'日</span></div>'
		+'<div style="display:flex;gap:2px">'+dayLabels+'<div class="streak-grid" style="flex:1">'+g+'</div></div>'
		+s;
}
