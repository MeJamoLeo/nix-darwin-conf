# Terry Black's（オースティンの BBQ 屋）の手描き風壁紙を SVG で吐く生成スクリプト。
# 使い方: python3 gen.py day|night out.svg   （day = DMS の light モード用、night = dark モード用）
# 本物の店の写真（昼・夜）と手持ちの T シャツの雰囲気を参考に Claude が描いた（2026-10-24）。
# 構図は1つで、色（C の辞書）と夜だけの要素（星・ネオンの光・街灯）が変わる。
#
# ★ 構図は「駐車場に立つ1人のカメラ」から全部計算する（物ごとに手で置くと視点がばらける）。
#   G(X, Z, Yw)：地面の座標（m。X=右、Z=奥、Yw=高さ）→ 画面。目の高さ EYE=1.5m、地平線 HY。
#   ピットハウスは正面が TH 傾いた箱で、W(s, t, h) で指す（s=角から正面沿いに左奥へ、
#   t=角から側面沿いに右奥へ、h=高さ m）。左の家は画面と平行（正面向き）で、奥に下がって床が高い。
#   駐車場の線は視心 (CVX, HY) へ集まる1点透視。構図を動かすときは HY / CVX / D / TH だけを触る。
#   PNG 化は ../home.nix の nix ビルドで行う。
import math, sys, random
mode = sys.argv[1]; out = sys.argv[2]
N = mode == "night"
C = dict(
  bg="#f3eee2", ink="#25272a", title="#25272a", sub="#3d7a37",
  sky="#cfe3ee", t1="#8fc274", t2="#7db863", t3="#6dab57", t4="#5f9e4c", tdark="#4a893c", tlight="#a4d088",
  rust="#9a5b34", rustd="#7a4426", screen="#4a3d2f", frame="#c9b48a", skirt="#ecebe4", skirtl="#c9cac4",
  skirtS="#d7d7d0", skirtSl="#b5b6b0", roof="#3b342d", house="#dccaa4", housel="#c4b088", shingle="#8f8e88",
  win="#3c4650", winframe="#f4f1e8", rail="#7a5a3c", stone="#b9b6ad", yellow="#e9b52c", ground="#d8d2c3",
  smoke="#c9cbcb", bboq="#e8572a", ty="#f2b632", sign="#2f6fb0", line="#fbfaf5")
if N:
  C.update(bg="#0e1422", ink="#05070c", title="#f3eee2", sub="#8fc274", sky="#0e1422",
  t1="#1f3a2e", t2="#1a3228", t3="#183026", t4="#14281f", tdark="#0f1f18", tlight="#24443a",
  rust="#4a3426", rustd="#3a281d", screen="#2b4f86", frame="#5a4a36", skirt="#a9b6cc", skirtl="#8592a8",
  skirtS="#7f8aa0", skirtSl="#667087", roof="#141820", house="#5b5446", housel="#4a4438", shingle="#353a44",
  win="#e7a65a", winframe="#9a9a92", rail="#3a2c20", stone="#4a4c52", yellow="#c99a24", ground="#1b2130",
  smoke="#3a4252", line="#c8ccd4")
def P(*p): return " ".join(f"{x:.1f},{y:.1f}" for x,y in p)
o=[]; a=o.append
a('<svg xmlns="http://www.w3.org/2000/svg" width="2160" height="1350" viewBox="0 0 2160 1350">')
a(f'''<defs>
<filter id="paper" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" seed="3"/><feColorMatrix values="0 0 0 0 0.45 0 0 0 0 0.40 0 0 0 0 0.32 0 0 0 {0.06 if N else 0.10} 0"/><feComposite in2="SourceGraphic" operator="in"/><feBlend in2="SourceGraphic" mode="{'screen' if N else 'multiply'}"/></filter>
<filter id="wc" x="-20%" y="-20%" width="140%" height="140%"><feTurbulence type="fractalNoise" baseFrequency="0.018" numOctaves="3" seed="7" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="46" xChannelSelector="R" yChannelSelector="G" result="d"/><feTurbulence type="fractalNoise" baseFrequency="0.06" numOctaves="2" seed="11" result="t"/><feColorMatrix in="t" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1.6 -0.35" result="ta"/><feComposite in="d" in2="ta" operator="arithmetic" k1="0.55" k2="0.55"/></filter>
<filter id="wcs" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="5" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="7" xChannelSelector="R" yChannelSelector="G"/></filter>
<filter id="ink" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency="0.04" numOctaves="2" seed="2" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="3.5" xChannelSelector="R" yChannelSelector="G"/></filter>
<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14"/></filter>
<filter id="glow2" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="40"/></filter>
<pattern id="rustp" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="10" height="10" fill="{C['rust']}"/><rect width="3" height="10" fill="{C['rustd']}"/></pattern>
<pattern id="skirtp" width="14" height="14" patternUnits="userSpaceOnUse"><rect width="14" height="14" fill="{C['skirt']}"/><rect width="3" height="14" fill="{C['skirtl']}"/></pattern>
<pattern id="skirtSp" width="12" height="12" patternUnits="userSpaceOnUse"><rect width="12" height="12" fill="{C['skirtS']}"/><rect width="3" height="12" fill="{C['skirtSl']}"/></pattern>
<pattern id="sidingp" width="20" height="16" patternUnits="userSpaceOnUse"><rect width="20" height="16" fill="{C['house']}"/><rect y="13" width="20" height="3" fill="{C['housel']}"/></pattern>
<pattern id="shinglep" width="26" height="14" patternUnits="userSpaceOnUse"><rect width="26" height="14" fill="{C['shingle']}"/><path d="M0 13 H26 M13 0 V7 M0 7 H26 M6 7 V13 M19 7 V13" stroke="{C['ink']}" stroke-opacity="0.25" stroke-width="1.2"/></pattern>
</defs>''')
a(f'<rect width="2160" height="1350" fill="{C["bg"]}" filter="url(#paper)"/>')
if N:
  for i in range(260):
    random.seed(i); x=random.uniform(0,2160); y=random.uniform(0,560); r=random.choice([1,1,1.4,2])
    a(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="#f3eee2" opacity="{random.uniform(.3,.8):.2f}"/>')
else:
  pass
a(f'<text x="1080" y="225" text-anchor="middle" font-family="Dancing Script" font-weight="700" font-size="176" fill="{C["title"]}">Terry Black’s</text>')
a(f'<text x="1080" y="297" text-anchor="middle" font-family="DejaVu Sans" font-size="32" letter-spacing="5" fill="{C["sub"]}">ORIGINAL TEXAS BARBECUE · AUSTIN, TX</text>')
if not N:
  a(f'<path filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.2" stroke-linecap="round" d="M520 420 q45 -34 95 -4 q40 -30 90 2 q55 -38 110 -2 M1300 400 q40 -30 88 -2 q55 -36 112 0 q38 -26 80 6"/>')

# ---------- カメラ ----------
HY, CVX, D, EYE = 925.0, 1080.0, 1522.0, 1.5
TH = math.radians(37.5)
def G(X, Z, Yw=0.0): return (CVX + D*X/Z, HY - D*(Yw-EYE)/Z)
def px(m, Z): return D*m/Z            # 奥行き Z にある長さ m の見かけの px
U = (-math.cos(TH), math.sin(TH))     # 正面沿い（左奥へ）
V = (math.sin(TH), math.cos(TH))      # 側面沿い（右奥へ）
CW = (3.477, 14.7)                    # ピットハウス手前の角（画面 x≈1440）
WALL = 3.1
def Wxz(s,t): return (CW[0]+s*U[0]+t*V[0], CW[1]+s*U[1]+t*V[1])
def W(s,t,h=0.0):
  X,Z=Wxz(s,t); return G(X,Z,h)
FL, SL = 6.55, 3.23                   # 正面・側面の長さ m
def quadF(s0,s1,h0,h1,t=0.0): return [W(s0,t,h1),W(s1,t,h1),W(s1,t,h0),W(s0,t,h0)]
def quadS(t0,t1,h0,h1,s=0.0): return [W(s,t0,h1),W(s,t1,h1),W(s,t1,h0),W(s,t0,h0)]
def poly(pts, **kw):
  attr=" ".join(f'{k.replace("_","-")}="{v}"' for k,v in kw.items()); return f'<polygon points="{P(*pts)}" {attr}/>'
def seg(p,q): return f"M{p[0]:.1f} {p[1]:.1f} L{q[0]:.1f} {q[1]:.1f}"

# ---------- 木（右を重く、左の家の屋根の上は空を抜く） ----------
random.seed(4)
cl=[(1150,560,260,170,"t2"),(1420,500,280,180,"t3"),(1700,560,260,190,"t2"),(1930,680,220,170,"t1"),(1290,700,230,120,"tdark"),
    (1600,700,220,120,"tdark"),(1020,680,170,120,"t1"),(1500,410,150,80,"tlight"),(1800,470,130,70,"tlight"),(2080,800,150,140,"t4"),
    (230,790,200,150,"t1"),(90,720,160,140,"t2"),(330,860,140,90,"tdark")]
a('<g filter="url(#wc)">'+"".join(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{C[c]}" opacity="{0.8 if c=="tdark" else 1}"/>' for x,y,rx,ry,c in cl)+'</g>')
segs=[]
for _ in range(90):
  x0,y0,rx,ry,_c=random.choice(cl); t=random.uniform(0,2*math.pi); x=x0+rx*math.cos(t); y=y0+ry*math.sin(t)
  if y>840: continue
  segs.append(f"M{x:.0f} {y:.0f} q8 -10 18 -2")
a(f'<g filter="url(#ink)" fill="none" stroke="{"#2f4a2a" if not N else "#0a1410"}" stroke-width="2" stroke-linecap="round"><path d="{" ".join(segs)}"/><path d="M1180 760 q-10 -90 40 -160 M1760 800 q10 -90 70 -150 M1800 720 q-40 -50 -30 -110 M260 880 q0 -60 -40 -110"/></g>')

# ---------- 地面と駐車場（平らな物は建物より先に描く） ----------
gnd=[(0,1000),(2160,1000),(2160,1350),(0,1350)]
a(poly(gnd, fill=C["ground"], opacity="0.4", filter="url(#wc)"))
# ピットハウス脇の通路（側面に沿って VPR へ）
VPRs=(CVX+D*math.tan(TH),HY)
a(poly([(1590,1350),(2160,1350),(2160,1180),(1760,1060),(1600,1075)], fill=C["ground"], opacity="0.25", filter="url(#wc)"))
lw=0.16
lines=[]
for X in (-12.0,-9.3,-6.6,-3.9):
  z0,z1=22.5,6.0
  lines.append(poly([G(X-lw/2,z0),G(X+lw/2,z0),G(X+lw/2,z1),G(X-lw/2,z1)]))
lines.append(poly([G(-13.5,22.5),G(-1.6,22.5),G(-1.6,22.0),G(-13.5,22.0)]))   # 車止めライン
a(f'<g filter="url(#wcs)" fill="{C["line"]}" stroke="{C["ink"]}" stroke-opacity="0.35" stroke-width="1.2">{"".join(lines)}</g>')

# ---------- 石垣（ピットハウスの右奥、通路の向こう） ----------
st=[G(6,26,2.5),G(13,26,2.3),G(13,26,0),G(6,26,0)]
a(poly(st, fill=C["stone"], filter="url(#wc)"))
stn=[]
for r in range(6):
  for c in range(10):
    X=6.3+c*0.72+(r%2)*0.36; Yw=0.25+r*0.4
    if X<12.8:
      x,y=G(X,26,Yw); stn.append(f'<ellipse cx="{x:.0f}" cy="{y:.0f}" rx="{px(0.33,26):.0f}" ry="{px(0.18,26):.0f}"/>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="1.6" opacity="0.7">{"".join(stn)}</g>')

# ---------- 左の家（正面向き・Z=23・床 0.8m・寄棟） ----------
HZ, HX0, HX1, DECK, HTOP = 23.0, -10.5, -1.6, 0.8, 3.8
wall=[G(HX0,HZ,HTOP),G(HX1,HZ,HTOP),G(HX1,HZ,DECK),G(HX0,HZ,DECK)]
roof=[G(HX0-0.5,22.5,HTOP),G(HX1+0.5,22.5,HTOP),G(HX1-2.2,26.5,6.0),G(HX0+2.4,26.5,6.0)]
deckf=[G(HX0-0.3,22.0,DECK),G(HX1+0.3,22.0,DECK),G(HX1+0.3,22.0,0),G(HX0-0.3,22.0,0)]
wins=[(-9.9,-8.7),(-8.2,-7.0),(-4.2,-3.0)]
door=(-6.2,-5.0)
a('<g filter="url(#wcs)">')
a(poly(wall, fill="url(#sidingp)")); a(poly(roof, fill="url(#shinglep)")); a(poly(deckf, fill=C["rail"], opacity="0.55"))
for x0,x1 in wins: a(poly([G(x0,HZ,3.2),G(x1,HZ,3.2),G(x1,HZ,1.7),G(x0,HZ,1.7)], fill=C["win"]))
a(poly([G(door[0],HZ,3.3),G(door[1],HZ,3.3),G(door[1],HZ,DECK),G(door[0],HZ,DECK)], fill="#7a3b2e"))
mx,my=G(-5.85,HZ,2.6); a(f'<circle cx="{mx:.0f}" cy="{my:.0f}" r="{px(0.28,HZ):.0f}" fill="#e9b52c"/>')
mx,my=G(-5.35,HZ,2.0); a(f'<circle cx="{mx:.0f}" cy="{my:.0f}" r="{px(0.24,HZ):.0f}" fill="#3f8f8a"/>')
a(poly([G(-6.0,HZ,1.5),G(-5.2,HZ,1.5),G(-5.2,HZ,1.3),G(-6.0,HZ,1.3)], fill="#c94a3a"))
a('</g>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.2" stroke-linejoin="round">')
a(poly(wall)); a(poly(roof)); a(poly(deckf))
for x0,x1 in wins:
  a(poly([G(x0,HZ,3.2),G(x1,HZ,3.2),G(x1,HZ,1.7),G(x0,HZ,1.7)], stroke=C["winframe"], stroke_width="5"))
  m=(x0+x1)/2; a(f'<path stroke="{C["winframe"]}" stroke-width="3.5" d="{seg(G(m,HZ,3.2),G(m,HZ,1.7))}"/>')
a(poly([G(door[0],HZ,3.3),G(door[1],HZ,3.3),G(door[1],HZ,DECK),G(door[0],HZ,DECK)]))
# 手すり（デッキの前、Z=22）
rl=[seg(G(HX0-0.3,22.0,1.8),G(HX1+0.3,22.0,1.8))]
X=HX0-0.3
while X<=HX1+0.31:
  rl.append(seg(G(X,22.0,0),G(X,22.0,1.8))); X+=1.3
a(f'<path stroke="{C["rail"]}" stroke-width="6" d="{" ".join(rl)}"/>')
a('</g>')

# ---------- ピットハウス ----------
# 煙突・換気口・煙（屋根の上、少し奥）
sk=[W(0.7,1.6,3.6),W(0.7,1.6,6.2)]; skz=Wxz(0.7,1.6)[1]
top=sk[1]; bend=(top[0]+px(0.9,skz), top[1]-px(0.5,skz))
sw=px(0.42,skz)
sk2=[W(1.5,1.2,3.6),W(1.5,1.2,5.0)]; s2z=Wxz(1.5,1.2)[1]
vp=[W(5.6,0.9,3.6),W(5.6,0.9,5.5)]; vz=Wxz(5.6,0.9)[1]
a(f'<g filter="url(#wcs)"><ellipse cx="{bend[0]+40:.0f}" cy="{bend[1]-50:.0f}" rx="85" ry="42" fill="{C["smoke"]}" opacity="0.6"/><ellipse cx="{bend[0]+110:.0f}" cy="{bend[1]-120:.0f}" rx="100" ry="48" fill="{C["smoke"]}" opacity="0.5"/>'
  f'<rect x="{vp[0][0]-px(0.06,vz):.1f}" y="{vp[1][1]:.1f}" width="{px(0.12,vz):.1f}" height="{vp[0][1]-vp[1][1]:.1f}" fill="{C["rustd"]}"/>'
  f'<rect x="{vp[1][0]-px(0.3,vz):.1f}" y="{vp[1][1]-px(0.8,vz):.1f}" width="{px(0.6,vz):.1f}" height="{px(0.8,vz):.1f}" rx="6" fill="{"#b1b4b6" if not N else "#4a505c"}"/></g>')
pd=f"M{sk[0][0]:.1f} {sk[0][1]:.1f} L{top[0]:.1f} {top[1]+px(0.6,skz):.1f} Q{top[0]:.1f} {top[1]:.1f} {bend[0]:.1f} {bend[1]:.1f}"
pd2=seg(*sk2)
a(f'<g filter="url(#ink)" fill="none" stroke-linecap="round"><path d="{pd}" stroke="{C["ink"]}" stroke-width="{sw+7:.1f}"/><path d="{pd}" stroke="{C["rust"]}" stroke-width="{sw:.1f}"/>'
  f'<path d="{pd2}" stroke="{C["ink"]}" stroke-width="{px(0.3,s2z)+6:.1f}"/><path d="{pd2}" stroke="{C["rustd"]}" stroke-width="{px(0.3,s2z):.1f}"/>'
  f'<rect x="{vp[1][0]-px(0.3,vz):.1f}" y="{vp[1][1]-px(0.8,vz):.1f}" width="{px(0.6,vz):.1f}" height="{px(0.8,vz):.1f}" rx="6" stroke="{C["ink"]}" stroke-width="2.4"/>'
  f'<path stroke="{"#6f7478" if not N else "#556070"}" stroke-width="2" d="M{bend[0]:.0f} {bend[1]:.0f} c25 -25 0 -50 40 -70 c30 -15 25 -45 60 -60"/></g>')
# 上部の箱（目より上なので天面は見えない。鉛直の面だけ）
ub_s0, ub_s1, ub_t, ub_h0, ub_h1 = 0.9, 5.4, 0.8, 3.55, 4.5
ubF=quadF(ub_s0,ub_s1,ub_h0,ub_h1,t=ub_t); ubS=[W(ub_s0,ub_t,ub_h1),W(ub_s0,ub_t+1.6,ub_h1),W(ub_s0,ub_t+1.6,ub_h0),W(ub_s0,ub_t,ub_h0)]
# 屋根の枠（軒。前と右に 0.3m 張り出す）
eF=quadF(-0.3,FL+0.35,3.1,3.55,t=-0.3); eS=quadS(-0.3,SL+0.3,3.1,3.55,s=-0.3)
soffit=[W(-0.3,-0.3,3.1),W(FL+0.35,-0.3,3.1),W(FL,0,3.1),W(0,0,3.1),W(0,SL,3.1),W(-0.3,SL+0.3,3.1)]
H18, H55 = WALL*(1-0.18), WALL*(1-0.55)
a('<g filter="url(#wcs)">')
a(poly(ubF, fill=C["roof"])); a(poly(ubS, fill=C["roof"], opacity="0.85"))
a(poly(quadF(0,FL,H18,WALL), fill="url(#rustp)")); a(poly(quadF(0,FL,H55,H18), fill=C["screen"])); a(poly(quadF(0,FL,0,H55), fill="url(#skirtp)"))
a(poly(quadS(0,SL,H18,WALL), fill="url(#rustp)")); a(poly(quadS(0,SL,H55,H18), fill=C["screen"], opacity="0.9")); a(poly(quadS(0,SL,0,H55), fill="url(#skirtSp)"))
a(poly(soffit, fill=C["rustd"], opacity="0.8"))
a(poly(eF, fill="url(#rustp)")); a(poly(eS, fill="url(#rustp)"))
a('</g>')
if N:
  a(poly(quadF(0.1,FL-0.1,H55+0.1,H18-0.1), fill="#6fa8ff", opacity="0.55", filter="url(#glow)"))
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.6" stroke-linejoin="round">')
a(poly(ubF)); a(poly(ubS)); a(poly(quadF(0,FL,0,WALL))); a(poly(quadS(0,SL,0,WALL))); a(poly(eF)); a(poly(eS))
for h in (H18,H55): a(f'<path d="{seg(W(FL,0,h),W(0,0,h))} L{W(0,SL,h)[0]:.1f} {W(0,SL,h)[1]:.1f}"/>')
m=[seg(W(s,0,H18),W(s,0,H55)) for s in (1.6,3.2,4.8)]+[seg(W(0,1.6,H18),W(0,1.6,H55))]
m.append(seg(W(FL,0,2.0),W(0,0,2.0)))
a(f'<path stroke="{C["frame"]}" stroke-width="6" d="{" ".join(m)}"/>')
a(f'<path stroke-width="2" d="{" ".join(seg(W(s,ub_t,ub_h0),W(s+0.5,ub_t,ub_h1)) for s in (1.2,2.0,2.8,3.6,4.4))}"/>')
a('</g>')
# 看板の文字（上部の箱の前面に立つ。面の傾きと奥行きの縮みを行列で当てる）
def plane_text(sc, h, cap_m, body):
  c=W(sc,ub_t,h); p0=W(sc+1,ub_t,h); p1=W(sc-1,ub_t,h); Zc=Wxz(sc,ub_t)[1]
  dx=(p1[0]-p0[0])/2; dy=(p1[1]-p0[1])/2; k=D/Zc
  size=k*cap_m/0.73
  return f'<g transform="translate({c[0]:.1f},{c[1]:.1f}) matrix({dx/k:.4f},{dy/k:.4f},0,1,0,0)">'+body.format(size=f"{size:.1f}")+'</g>'
ty='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" letter-spacing="2" fill="'+C["ty"]+'" stroke="'+C["ink"]+'" stroke-width="1.6">TERRY BLACK’S</text>'
bq_o='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" letter-spacing="10" fill="none" stroke="#1b1612" stroke-width="16" stroke-linejoin="round">BBQ</text>'
bq='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" letter-spacing="10" fill="'+C["bboq"]+'" stroke="#fff1d0" stroke-width="3.5">BBQ</text>'
SC=3.15
if N:
  gb='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" letter-spacing="10" fill="#ff5a20" stroke="#ff7a30" stroke-width="18">BBQ</text>'
  gt='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" letter-spacing="2" fill="#ffcf5a" stroke="#ffcf5a" stroke-width="10">TERRY BLACK’S</text>'
  a('<g filter="url(#glow2)" opacity="0.9">'+plane_text(SC,3.95,1.0,gb)+plane_text(SC,5.25,0.36,gt)+'</g>')
a(plane_text(SC,5.25,0.36,ty)); a(plane_text(SC,3.95,1.0,bq_o+bq))
# 柱とボラード
posts=[(W(0,0,0),W(0,0,3.55),Wxz(0,0)[1]),(W(0,SL,0),W(0,SL,3.55),Wxz(0,SL)[1])]
pr="".join(f'<rect x="{b[0]-px(0.1,z):.1f}" y="{t[1]:.1f}" width="{px(0.2,z):.1f}" height="{b[1]-t[1]:.1f}"/>' for b,t,z in posts)
bol=[]
for s,t in ((0.9,-0.45),(-0.45,0.4),(-0.45,1.4),(-0.45,2.4),(-0.45,3.4)):
  X,Z=Wxz(s,t); b=G(X,Z,0); tp=G(X,Z,1.0); w=px(0.22,Z)
  bol.append(f'<rect x="{b[0]-w/2:.1f}" y="{tp[1]:.1f}" width="{w:.1f}" height="{b[1]-tp[1]:.1f}" rx="{w/3:.1f}"/>')
a(f'<g filter="url(#wcs)" fill="{C["rail"]}">{pr}</g><g filter="url(#wcs)" fill="{C["yellow"]}">{"".join(bol)}</g>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2">{pr}{"".join(bol)}</g>')

# ---------- 手前の小物（車止めブロック・標識） ----------
cs=[]
for Xc in (-10.65,-7.95,-5.25):
  cs.append(poly([G(Xc-0.9,22.0,0.15),G(Xc+0.9,22.0,0.15),G(Xc+0.9,22.0,0),G(Xc-0.9,22.0,0)]))
a(f'<g filter="url(#wcs)" fill="{C["yellow"]}">{"".join(cs)}</g>')
sb,stp=G(-3.0,21.0,0),G(-3.0,21.0,2.1); sw_=px(0.45,21.0)
a(f'<g filter="url(#ink)" stroke="{C["ink"]}" stroke-width="2.4"><path d="{seg(sb,stp)}"/><rect x="{stp[0]-sw_/2:.1f}" y="{stp[1]-sw_*1.1:.1f}" width="{sw_:.1f}" height="{sw_*1.1:.1f}" fill="{C["sign"]}"/></g>')
# 街灯（夜）：家とピットハウスの間、少し手前
if N:
  lx,ly_=G(-2.4,21.0,4.2)
  pb=G(-2.4,21.0,0)
  a(f'<path d="{seg(pb,(lx,ly_))}" stroke="#05070c" stroke-width="5"/>')
  a(f'<circle cx="{lx:.0f}" cy="{ly_:.0f}" r="70" fill="#6fa8ff" filter="url(#glow2)" opacity="0.9"/>')
  rays="".join(f'<path d="M{lx:.0f} {ly_:.0f} L{lx+math.cos(math.radians(t))*L:.0f} {ly_+math.sin(math.radians(t))*L:.0f}"/>' for t,L in [(200,420),(-35,380),(20,180),(160,200),(-90,160),(250,260),(290,150)])
  a(f'<g stroke="#9cc4ff" stroke-width="3" opacity="0.6" filter="url(#ink)">{rays}</g><circle cx="{lx:.0f}" cy="{ly_:.0f}" r="9" fill="#ffffff"/>')

# ---------- 帯（駐車場の線の上に乗るので地色で下敷き） ----------
a(f'<rect x="640" y="1212" width="880" height="86" fill="{C["bg"]}" opacity="0.88" filter="url(#wcs)"/>')
a(f'<g filter="url(#ink)" stroke="{C["title"]}" stroke-width="2.2"><path d="M660 1218 L1500 1218 M660 1291 L1500 1291"/></g>')
a(f'<text x="1080" y="1268" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="40" letter-spacing="8" fill="{C["sub"]}">BRISKET SAUSAGE &amp; RIBS</text>')
a('</svg>')
open(out,"w").write("\n".join(o))
