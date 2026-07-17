function hydrate() {
	const d = window.__CP_DATA;
	if (!d) return;
	const novi = window.__NOVI_DATA || null;
	const vp = window.__VP || {w:1080, h:675};
	document.body.innerHTML = renderHUD(d)
		+'<div class="main">'
		+'<div class="col-left">'
			+'<div style="flex:1;display:flex;flex-direction:column;min-height:0;overflow:hidden">'+renderPlayerStatus(d)+'</div>'
			+'<div style="flex:1;min-height:0;display:flex;flex-direction:column">'+renderTodayVolume(d)+'</div>'
			+'<div style="flex:2;min-height:0;display:flex;flex-direction:column;gap:6px">'
				+renderVolumeHistory(d,'sum_xp','VOL · SUM_XP','var(--amber)')
				+renderVolumeHistory(d,'top3_sum','VOL · TOP3','var(--cyan)')
				+renderVolumeHistory(d,'perf','VOL · PERF','var(--green)')
			+'</div>'
		+'</div>'
		+'<div class="col-right">'
			+'<div class="col-right-top">'
				+renderDifficultyLog(d)
				+'<div class="panel" data-label="NOVI 成長" style="overflow:hidden">'+renderNoviTrend(novi)+'</div>'
			+'</div>'
			+'<div class="col-right-bottom" style="grid-template-columns:3fr 1fr 1fr">'
				+'<div class="panel" data-label="NOVISTEPS" style="overflow:hidden">'+renderNoviSteps(novi)+'</div>'
				+'<div class="panel accent-amber" data-label="STREAK" style="background:var(--dbg-streak)"><div class="panel-inner">'+renderStreakCalendar(d)+'</div></div>'
				+'<div class="panel accent-cyan" data-label="CONTEST" style="background:var(--dbg-speed)"><div class="panel-inner">'+renderContestList(d)+'</div></div>'
			+'</div>'
		+'</div>'
		+'</div>';

	const fc=(d.contests||[])[0];
	if(fc){const bt=document.getElementById('boss-timer');if(bt)setInterval(()=>{const diff=fc.start_epoch-Date.now()/1000;if(diff<=0){bt.textContent='LIVE';return;}bt.textContent=Math.floor(diff/3600)+':'+String(Math.floor((diff%3600)/60)).padStart(2,'0')+':'+String(Math.floor(diff%60)).padStart(2,'0');},1000);}
}
