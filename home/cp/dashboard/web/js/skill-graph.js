function renderSkillGraph(d) {
	const sg = d.skill_graph || {};
	const nodes = sg.nodes || [];
	const tiers = sg.tiers || [];
	if (!nodes.length) return '<div style="text-align:center;color:var(--dim);padding-top:20px">No data</div>';

	const byId = {};
	nodes.forEach(n => byId[n.id] = n);

	const W = 600, H = 600, cx = W/2, cy = H/2;
	// Dynamic radii based on number of tiers
	const numTiers = tiers.length - 1; // exclude tier 0
	const radii = [0];
	for (let i = 1; i <= numTiers; i++) radii.push(Math.round(30 + i * (245 / numTiers)));
	const tierGroups = {};
	nodes.forEach(n => { (tierGroups[n.tier] = tierGroups[n.tier] || []).push(n); });

	const pos = {};
	const center = nodes.find(n => n.tier === 0);
	if (center) pos[center.id] = {x: cx, y: cy};

	const t1 = tierGroups[1] || [];
	const t1Angles = {};
	t1.forEach((n, i) => {
		const angle = (i / t1.length) * Math.PI * 2 - Math.PI/2;
		t1Angles[n.id] = angle;
		pos[n.id] = {x: cx + Math.cos(angle) * radii[1], y: cy + Math.sin(angle) * radii[1]};
	});

	function findT1Ancestor(n) {
		let cur = n;
		while (cur && cur.tier > 1) cur = byId[cur.parent];
		if (cur && cur.tier === 1) return cur.id;
		return null;
	}

	function getDepth(n) {
		let d = 0, cur = n;
		while (cur.parent && byId[cur.parent]) { d++; cur = byId[cur.parent]; }
		return d;
	}
	const maxDepth = Math.max(...nodes.map(getDepth));
	const depthRadii = [];
	for (let i = 0; i <= maxDepth; i++) {
		depthRadii[i] = 30 + i * (260 / maxDepth);
	}

	const childMap = {};
	nodes.forEach(n => { if (n.parent) (childMap[n.parent] = childMap[n.parent] || []).push(n.id); });

	const leafCount = {};
	function countLeaves(id) {
		if (!childMap[id]) { leafCount[id] = 1; return 1; }
		let sum = 0;
		childMap[id].forEach(cid => sum += countLeaves(cid));
		leafCount[id] = sum;
		return sum;
	}
	countLeaves('base');
	const totalLeaves = leafCount['base'];

	const nodeAngles = {};
	function layoutSubtree(id, angleStart, angleEnd) {
		const node = byId[id];
		if (!node || node.tier === 0) {} else {
			const mid = (angleStart + angleEnd) / 2;
			nodeAngles[id] = mid;
			const r = depthRadii[getDepth(node)];
			pos[id] = {x: cx + Math.cos(mid) * r, y: cy + Math.sin(mid) * r};
		}
		if (!childMap[id]) return;
		const children = childMap[id];
		let cursor = angleStart;
		children.forEach(cid => {
			const weight = leafCount[cid] / leafCount[id];
			const childEnd = cursor + weight * (angleEnd - angleStart);
			layoutSubtree(cid, cursor, childEnd);
			cursor = childEnd;
		});
	}
	layoutSubtree('base', -Math.PI/2, Math.PI * 3/2);

	const tierColor = {};
	tiers.forEach(t => tierColor[t.tier] = t.color);
	const nodeStroke = '#4a8a8a';

	let s = '<svg width="100%" height="100%" viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg">';
	s += '<defs>';
	tiers.forEach(t => {
		if (t.tier === 0) return;
		const inner = radii[t.tier - 1] || 0;
		const outer = radii[t.tier];
		const mid = (inner + outer) / 2;
		s += '<radialGradient id="zone'+t.tier+'" cx="50%" cy="50%" r="'+(outer/Math.max(W,H)*100).toFixed(1)+'%">';
		s += '<stop offset="'+(inner/outer*100).toFixed(0)+'%" stop-color="'+t.color+'" stop-opacity="0"/>';
		s += '<stop offset="'+(mid/outer*100).toFixed(0)+'%" stop-color="'+t.color+'" stop-opacity="0.08"/>';
		s += '<stop offset="100%" stop-color="'+t.color+'" stop-opacity="0.03"/>';
		s += '</radialGradient>';
	});
	s += '</defs>';

	// ティアゾーン（AtCoderカラー帯 — リング型で重ならない）
	const acBands = {1:'#c06000', 2:'#008000', 3:'#00c0c0', 4:'#0060ff'};
	[1, 2, 3, 4].forEach(t => {
		if (!radii[t]) return;
		const inner = t === 1 ? 0 : radii[t-1] + 20;
		const outer = radii[t] + 20;
		// clipPathでリング（ドーナツ）を作る
		const clipId = 'tierClip'+t;
		s += '<defs><clipPath id="'+clipId+'"><path d="M'+(cx-outer-1)+','+(cy-outer-1)+' h'+(2*outer+2)+' v'+(2*outer+2)+' h'+(-2*outer-2)+' Z';
		if(inner > 0) s += ' M'+cx+','+(cy-inner)+' a'+inner+','+inner+' 0 1,0 0,'+(2*inner)+' a'+inner+','+inner+' 0 1,0 0,'+(-2*inner)+' Z';
		s += '"/></clipPath></defs>';
		s += '<circle cx="'+cx+'" cy="'+cy+'" r="'+outer+'" fill="'+(acBands[t]||'#1a1a1a')+'" opacity="0.08" clip-path="url(#'+clipId+')"/>';
	});
	[1, 2, 3, 4].forEach(t => {
		if (!radii[t]) return;
		const r = (radii[t-1] + radii[t]) / 2 + 10;
		s += '<circle cx="'+cx+'" cy="'+cy+'" r="'+r+'" fill="none" stroke="'+(acBands[t]||'#1a1a1a')+'" stroke-width="0.5" stroke-dasharray="4,6" opacity="0.25"/>';
	});
	tiers.forEach(t => {
		if (t.tier === 0) return;
		const r = (radii[t.tier-1] + radii[t.tier]) / 2 + 10;
		s += '<text x="'+(cx+r-5)+'" y="'+(cy-4)+'" fill="'+(acBands[t.tier]||t.color)+'" font-size="7" font-family="monospace" opacity="0.5">'+t.label+'</text>';
	});

	nodes.forEach(n => {
		if (!n.parent || !pos[n.id] || !pos[n.parent]) return;
		const p1 = pos[n.parent], p2 = pos[n.id];
		const prog = n.progress ? n.progress[0] / n.progress[1] : 0;
		const opacity = prog > 0 ? 0.4 + prog * 0.6 : 0.1;
		s += '<line x1="'+p1.x.toFixed(1)+'" y1="'+p1.y.toFixed(1)+'" x2="'+p2.x.toFixed(1)+'" y2="'+p2.y.toFixed(1)+'" stroke="'+nodeStroke+'" stroke-width="0.8" opacity="'+opacity.toFixed(2)+'"/>';
	});

	nodes.forEach(n => {
		const p = pos[n.id];
		if (!p) return;
		const prog = n.progress ? n.progress[0] / n.progress[1] : 0;
		const done = n.progress && n.progress[0] >= n.progress[1];
		const m = n.mastery || [0,0,0]; // [untouched, touched, mastered]
		const allMastered = m[2] > 0 && m[0] === 0 && m[1] === 0;
		const hasTouched = m[1] > 0 || m[2] > 0;
		const r = n.tier === 0 ? 16 : 12;

		// 3-state glow: mastered=gold, touched=nodeStroke, untouched=none
		if (allMastered) {
			s += '<circle cx="'+p.x.toFixed(1)+'" cy="'+p.y.toFixed(1)+'" r="'+(r+5)+'" fill="#d4a017" opacity="0.15"/>';
			s += '<circle cx="'+p.x.toFixed(1)+'" cy="'+p.y.toFixed(1)+'" r="'+(r+3)+'" fill="#d4a017" opacity="0.08"/>';
		} else if (done) {
			s += '<circle cx="'+p.x.toFixed(1)+'" cy="'+p.y.toFixed(1)+'" r="'+(r+4)+'" fill="'+nodeStroke+'" opacity="0.12"/>';
		}

		// Node fill: mastered=gold tint, touched=teal, untouched=dark
		const fill = allMastered ? '#141408' : (hasTouched ? '#081414' : '#040a0a');
		const stroke = allMastered ? '#d4a017' : nodeStroke;
		s += '<circle cx="'+p.x.toFixed(1)+'" cy="'+p.y.toFixed(1)+'" r="'+r+'" fill="'+fill+'" stroke="'+stroke+'" stroke-width="'+(allMastered ? 2 : done ? 1.5 : 0.6)+'" opacity="'+(hasTouched ? 1 : 0.35)+'"/>';

		if (prog > 0 && !done) {
			const angle = prog * Math.PI * 2;
			const x1 = p.x, y1 = p.y - r;
			const x2 = p.x + Math.sin(angle) * r;
			const y2 = p.y - Math.cos(angle) * r;
			const large = angle > Math.PI ? 1 : 0;
			s += '<path d="M'+x1.toFixed(1)+','+y1.toFixed(1)+' A'+r+','+r+' 0 '+large+' 1 '+x2.toFixed(1)+','+y2.toFixed(1)+'" fill="none" stroke="'+nodeStroke+'" stroke-width="2" opacity="0.9"/>';
		}

		if (allMastered) {
			// Gold star for fully mastered (SRS graduated)
			s += '<text x="'+p.x.toFixed(1)+'" y="'+(p.y+1).toFixed(1)+'" fill="#d4a017" font-size="10" text-anchor="middle" dominant-baseline="middle">★</text>';
		} else if (done) {
			// Checkmark for all AC'd (but not all SRS graduated)
			s += '<text x="'+p.x.toFixed(1)+'" y="'+(p.y+1).toFixed(1)+'" fill="'+nodeStroke+'" font-size="9" text-anchor="middle" dominant-baseline="middle">✓</text>';
		}

		const dx = p.x - cx, dy = p.y - cy;
		const dist = Math.sqrt(dx*dx + dy*dy) || 1;
		const labelDist = r + 8;
		const lx = n.tier === 0 ? p.x : p.x + dx/dist * labelDist;
		const ly = n.tier === 0 ? p.y + r + 9 : p.y + dy/dist * labelDist + 3;
		const anchor = n.tier === 0 ? 'middle' : (dx > 20 ? 'start' : dx < -20 ? 'end' : 'middle');
		s += '<text x="'+lx.toFixed(1)+'" y="'+ly.toFixed(1)+'" fill="'+(prog > 0 ? '#8ababa' : '#2a4a4a')+'" font-size="7" text-anchor="'+anchor+'" font-family="monospace">'+n.label+'</text>';

		if (n.progress && !allMastered) {
			const masteredCount = m[2] || 0;
			const label = masteredCount > 0 ? masteredCount+'★'+'/'+n.progress[1] : n.progress[0]+'/'+n.progress[1];
			s += '<text x="'+p.x.toFixed(1)+'" y="'+(p.y+3).toFixed(1)+'" fill="'+(masteredCount > 0 ? '#d4a017' : prog > 0 ? '#8ababa' : '#2a4a4a')+'" font-size="6" text-anchor="middle" font-family="monospace">'+label+'</text>';
		}
	});

	s += '</svg>';
	return s;
}
