# Terry Black's（オースティンの BBQ 屋）の手描き風壁紙を SVG で吐く生成スクリプト。
# 使い方: python3 gen.py day|night out.svg   （day = DMS の light モード用、night = dark モード用）
# 本物の店の写真（昼・夜）と手持ちの T シャツの雰囲気を参考に Claude が描いた（2026-10-24）。
# 構図は1つで、色（C の辞書）と夜だけの要素（星・ネオンの光・街灯）が変わる。
#
# ★ 構図は「駐車場に立つ1人のカメラ」から全部計算する（物ごとに手で置くと視点がばらける）。
#   G(X, Z, Yw)：地面の座標（m。X=右、Z=奥、Yw=高さ）→ 画面。目の高さ EYE=1.5m、地平線 HY。
#   ピットハウスは正面が TH 傾いた箱で、W(s, t, h) で指す（s=角から正面沿いに左奥へ、
#   t=角から側面沿いに右奥へ、h=高さ m）。左の家は THH だけ振った箱で Hp(s, d, h) で指す（s=右手前の角から正面沿いに左奥へ、
#   d=奥行き、負なら家の前）。奥に下がって床が高い。駐車場は家の向きに揃える。構図を動かすときは HY / CVX / D / TH だけを触る。
#   PNG 化は ../home.nix の nix ビルドで行う。
import math, sys, random
mode = sys.argv[1]; out = sys.argv[2]
N = mode == "night"
# 細部は Street View（2022）の補助写真5枚で確認した（屋根の上の鉄骨の台・柱・右奥の薪と石垣・小物）。
# 色：木と看板と駐車場の線は T シャツの刷り寄り、建物は実物の写真（Street View 2022）寄り。
# 左の家はクリーム色の板張り、網戸は焦げ茶、波板は銀色に錆の筋、台と柱は黒い鉄骨。
C = dict(
  bg="#f6f5f0", ink="#2a2a28", title="#2a2a28", sub="#3f8a3a",
  sky="#cfe3ee", t1="#8cc063", t2="#74b250", t3="#5f9f45", t4="#4c8f3d", tdark="#3d7f36", tlight="#aad27f",
  rust="#9c978f", rustd="#6f6a63", screen="#3d3128", frame="#8a6a48", skirt="#c3c7ca", skirtl="#959ba1",
  skirtS="#aeb3b7", skirtSl="#848a90", roof="#3a3a38", house="#e3d7b9", housel="#c8ba96", shingle="#7f776c",
  win="#3b3f45", winframe="#2e2a26", rail="#7a5a3c", stone="#cdc6b4", stonel="#a39b88", yellow="#e8b834", ground="#d9d8d3",
  smoke="#cfd0d0", bboq="#e85a2c", ty="#f2c230", sign="#2f6fb0", line="#e8b834",
  pipe="#8a5a3e", piped="#4a4644", shadow="#6f8bb0", steel="#2b2c2e", galv="#c5c9cc", galvd="#9ea3a7",
  metal="#8f8d88", door="#c4392f", streak="#a07a5a", signbox="#2b2622", asphalt="#55585d",
  wood="#b8915e", cage="#2b2c2e", pole="#6e5a44", redroof="#b5463a")
if N:
  C.update(bg="#0e1422", ink="#05070c", title="#f3eee2", sub="#8fc274", sky="#0e1422",
  t1="#1f3a2e", t2="#1a3228", t3="#183026", t4="#14281f", tdark="#0f1f18", tlight="#24443a",
  rust="#3e4148", rustd="#2e3138", screen="#2a2420", frame="#4a3a2a", skirt="#8f9bb0", skirtl="#6c778c",
  skirtS="#6f7a8e", skirtSl="#566074", roof="#141416", house="#5e5848", housel="#4c4738", shingle="#33363c",
  win="#e7a65a", winframe="#1c1a18", rail="#3a2c20", stone="#4c4d50", stonel="#3a3b3e", yellow="#c9a234", ground="#1b2130",
  smoke="#3a4252", line="#c9a234", pipe="#4a3426", piped="#2a2a2c", shadow="#2a3a6a", steel="#08090b",
  galv="#5a6070", galvd="#454b58", metal="#3e4148", door="#7a2420", streak="#4a3a30", signbox="#141210",
  asphalt="#11151e", wood="#5a4630", cage="#08090b", pole="#2e2620", redroof="#5a2420")
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
# 左の家（THH 振った箱）
THH = math.radians(30.0)
UH = (-math.cos(THH), math.sin(THH)); VH = (math.sin(THH), math.cos(THH))
HR = (-1.6, 21.5)                       # 右手前の角（ピットハウスの裏に隠れる）
HLEN, HDEP, DECK, HTOP, RIDGE = 10.0, 7.0, 0.8, 3.8, 6.0
def Hxz(s_,d): return (HR[0]+s_*UH[0]+d*VH[0], HR[1]+s_*UH[1]+d*VH[1])
def Hp(s_,d,h=0.0):
  X,Z=Hxz(s_,d); return G(X,Z,h)
def hq(s0,s1,h0,h1,d=0.0): return [Hp(s0,d,h1),Hp(s1,d,h1),Hp(s1,d,h0),Hp(s0,d,h0)]

# ---------- 木（右を重く、左の家の屋根の上は空を抜く） ----------
random.seed(4)
cl=[(1150,560,260,170,"t2"),(1420,500,280,180,"t3"),(1700,560,260,190,"t2"),(1930,680,220,170,"t1"),(1290,760,240,170,"tdark"),
    (1600,780,240,170,"tdark"),(1020,680,170,120,"t1"),(1500,410,150,80,"tlight"),(1800,470,130,70,"tlight"),(2080,840,170,150,"t4"),
    (230,790,200,150,"t1"),(90,720,160,140,"t2"),(330,880,170,110,"tdark")]
a('<g filter="url(#wc)">'+"".join(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{C[c]}" opacity="{0.8 if c=="tdark" else 1}"/>' for x,y,rx,ry,c in cl)+'</g>')
segs=[]
for _ in range(90):
  x0,y0,rx,ry,_c=random.choice(cl); t=random.uniform(0,2*math.pi); x=x0+rx*math.cos(t); y=y0+ry*math.sin(t)
  if y>840: continue
  segs.append(f"M{x:.0f} {y:.0f} q8 -10 18 -2")
a(f'<g filter="url(#ink)" fill="none" stroke="{"#2f4a2a" if not N else "#0a1410"}" stroke-width="2" stroke-linecap="round"><path d="{" ".join(segs)}"/><path d="M1180 760 q-10 -90 40 -160 M1760 800 q10 -90 70 -150 M1800 720 q-40 -50 -30 -110 M260 880 q0 -60 -40 -110"/></g>')

# ---------- 地面と駐車場（平らな物は建物より先に描く） ----------
random.seed(21)
edge=[(x, 965+random.uniform(-14,14)) for x in range(0,2161,120)]
gnd=edge+[(2160,1350),(0,1350)]
a(f'<linearGradient id="gfade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{C["ground"]}" stop-opacity="{0.6 if N else 0.5}"/><stop offset="0.75" stop-color="{C["ground"]}" stop-opacity="{0.5 if N else 0.35}"/><stop offset="1" stop-color="{C["ground"]}" stop-opacity="0.1"/></linearGradient>')
a(poly(gnd, fill="url(#gfade)", filter="url(#wc)"))
# ピットハウス脇の通路（側面に沿って奥へ）
a(poly([(1480,1350),(2160,1350),(2160,995),(1720,985),(1560,1075)], fill=C["asphalt"], opacity="0.22", filter="url(#wc)"))
# 駐車場は左の家の向きに揃える（区画の線は家の奥行き方向 = 消失点 (CVX+D·tanTHH, HY) へ）
lw=0.16
lines=[]
def stall(s0, d0, d1):
  lines.append(poly([Hp(s0-lw/2,d0),Hp(s0+lw/2,d0),Hp(s0+lw/2,d1),Hp(s0-lw/2,d1)]))
for s0 in (0.9, 3.6, 6.3, 9.0):          # 奥の列（家の前・区画の奥行き 5.5m）
  stall(s0, -1.6, -7.1)
# 手前の列：通路をはさんで手前。家と同じ向きで、奥の端を地面の座標で並べる
for k in range(7):
  X0,Z0=-7.0+k*2.7*(-UH[0]), 16.0+k*2.7*(-UH[1])
  X1,Z1=X0-5.5*VH[0], Z0-5.5*VH[1]
  ox,oz=lw/2*(-UH[0]),lw/2*(-UH[1])
  lines.append(poly([G(X0-ox,Z0-oz),G(X0+ox,Z0+oz),G(X1+ox,Z1+oz),G(X1-ox,Z1-oz)]))
lines.append(poly([Hp(-0.6,-1.4),Hp(10.4,-1.4),Hp(10.4,-1.6),Hp(-0.6,-1.6)]))   # 車止めライン
a(f'<g filter="url(#wcs)" fill="{C["line"]}" stroke="{C["ink"]}" stroke-opacity="0.35" stroke-width="1.2">{"".join(lines)}</g>')
# 障害者用：ピットハウス寄りの区画は黄色の斜線、隣の区画に車椅子のマーク
hz_=[Hp(0.9,-1.6),Hp(3.6,-1.6),Hp(3.6,-7.1),Hp(0.9,-7.1)]
a(f'<clipPath id="hatch"><polygon points="{P(*hz_)}"/></clipPath>')
hs="".join(seg(Hp(x,-1.6),Hp(x+2.2,-7.1)) for x in [0.9-2.2+i*0.55 for i in range(10)])
a(f'<g clip-path="url(#hatch)"><path filter="url(#wcs)" stroke="{C["line"]}" stroke-width="{px(0.12,17):.1f}" d="{hs}"/></g>')
def ring(cs,cd,r,n=24): return [Hp(cs+r*math.cos(2*math.pi*i/n), cd+r*math.sin(2*math.pi*i/n)) for i in range(n)]
wz=Hxz(4.9,-4.6)[1]; ww=px(0.13,wz)
a(f'<g filter="url(#wcs)" fill="none" stroke="{C["line"]}" stroke-width="{ww:.1f}" stroke-linejoin="round">'
  f'<polygon points="{P(*ring(4.7,-4.9,0.62))}"/><path d="{seg(Hp(5.15,-3.95),Hp(4.95,-4.6))} L{Hp(5.65,-4.6)[0]:.1f} {Hp(5.65,-4.6)[1]:.1f} L{Hp(5.95,-5.35)[0]:.1f} {Hp(5.95,-5.35)[1]:.1f}"/></g>'
  f'<polygon filter="url(#wcs)" fill="{C["line"]}" points="{P(*ring(5.25,-3.55,0.17,12))}"/>')

# ---------- 電柱（右奥、石垣より奥） ----------
pb,pt=G(7.0,31,0),G(7.0,31,10.5); pw=px(0.3,31)
tr=G(7.0,31,8.0); tw=px(0.7,31); th_=px(1.1,31)
a(f'<g filter="url(#ink)" stroke="{C["ink"]}" stroke-width="1.8"><rect x="{pb[0]-pw/2:.1f}" y="{pt[1]:.1f}" width="{pw:.1f}" height="{pb[1]-pt[1]:.1f}" fill="{C["pole"]}"/>'
  f'<rect x="{tr[0]-pw/2-tw:.1f}" y="{tr[1]-th_:.1f}" width="{tw:.1f}" height="{th_:.1f}" rx="{tw/3:.1f}" fill="{C["galvd"]}"/><path fill="none" d="M{pt[0]-px(1.2,31):.1f} {pt[1]+px(0.6,31):.1f} L{pt[0]+px(1.2,31):.1f} {pt[1]+px(0.6,31):.1f}"/></g>')

# ---------- 石垣（石灰岩の積み石）と薪のケージ ----------
SWZ=26.0
st=[G(5,SWZ,3.0),G(16,SWZ,2.8),G(16,SWZ,0),G(5,SWZ,0)]
a(poly(st, fill=C["stone"], filter="url(#wc)"))
random.seed(13)
stn=[]
yw=0.0
while yw<2.9:
  hh=random.uniform(0.25,0.45); X=5.0+random.uniform(0,0.4)
  while X<16:
    w=random.uniform(0.5,1.3); x0,y0=G(X,SWZ,yw+hh); x1,y1=G(min(X+w,16),SWZ,yw)
    stn.append(f'<rect x="{x0:.0f}" y="{y0:.0f}" width="{x1-x0:.0f}" height="{y1-y0:.0f}"/>'); X+=w
  yw+=hh
a(f'<g filter="url(#ink)" fill="none" stroke="{C["stonel"]}" stroke-width="1.6">{"".join(stn)}</g>')
CZ=24.6
cg=[]
for i in range(4):
  X0=6.0+i*1.6; X1=X0+1.4
  q=[G(X0,CZ,1.4),G(X1,CZ,1.4),G(X1,CZ,0),G(X0,CZ,0)]
  random.seed(40+i)
  logs="".join(f'<circle cx="{G(random.uniform(X0+0.1,X1-0.1),CZ,0)[0]:.0f}" cy="{G(0,CZ,random.uniform(0.1,1.3))[1]:.0f}" r="{px(random.uniform(0.07,0.11),CZ):.0f}"/>' for _ in range(28))
  grid="".join(seg(G(X0+k*0.35,CZ,0),G(X0+k*0.35,CZ,1.4)) for k in range(1,4))+seg(G(X0,CZ,0.7),G(X1,CZ,0.7))
  cg.append(f'{poly(q, fill=C["wood"], opacity="0.85")}<g fill="{C["streak"]}" stroke="{C["ink"]}" stroke-width="1">{logs}</g><path d="{grid}" stroke="{C["cage"]}" stroke-width="1.6"/>{poly(q, fill="none", stroke=C["cage"], stroke_width="3")}')
a(f'<g filter="url(#ink)">{"".join(cg)}</g>')

# ---------- 左端の赤い金属屋根の建物（家のさらに奥・左） ----------
rw=[G(-18,27.5,3.0),G(-11.5,27.5,3.0),G(-11.5,27.5,0.6),G(-18,27.5,0.6)]
rr=[G(-18.5,27.0,3.0),G(-11.0,27.0,3.0),G(-11.5,29.5,4.4),G(-18,29.5,4.4)]
a(f'<g filter="url(#wcs)">{poly(rw, fill="url(#sidingp)")}{poly(rr, fill=C["redroof"])}</g><g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2">{poly(rw)}{poly(rr)}</g>')

# ---------- 左の家（THH 振った箱・床 0.8m・寄棟） ----------
wall=hq(HLEN,0,DECK,HTOP)
rend=[Hp(0,0,HTOP),Hp(0,HDEP,HTOP),Hp(0,HDEP,DECK),Hp(0,0,DECK)]          # 右の妻側（見える面）
e1,e2,e3=Hp(HLEN+0.5,-0.5,HTOP),Hp(-0.5,-0.5,HTOP),Hp(-0.5,HDEP+0.5,HTOP)
r1,r2=Hp(HLEN-HDEP/2,HDEP/2,RIDGE),Hp(HDEP/2,HDEP/2,RIDGE)
roof=[e1,e2,r2,r1]; hip=[e2,e3,r2]
deckf=hq(HLEN+0.3,-0.3,0,DECK,d=-1.0)
wins=[(8.9,7.9),(7.5,6.5),(2.6,1.6)]
door=(5.0,3.8)
a('<g filter="url(#wcs)">')
a(poly(rend, fill="url(#sidingp)", opacity="0.85")); a(poly(hip, fill="url(#shinglep)", opacity="0.85"))
a(poly(wall, fill="url(#sidingp)")); a(poly(roof, fill="url(#shinglep)")); a(poly(deckf, fill=C["rail"], opacity="0.55"))
random.seed(17)
for s0,s1 in wins:
  a(poly(hq(s0,s1,1.7,3.2), fill=C["win"]))
  for _ in range(3):                          # 窓の中に見える絵・飾り
    u=random.uniform(s1+0.1,s0-0.3); v=random.uniform(1.8,2.8)
    a(poly(hq(u+0.25,u,v,v+0.3), fill=random.choice(["#a8483a","#c9a24a","#5a7f8a","#8a6a9a"]), opacity="0.8"))
mz=Hxz(9.45,0)[1]; mc=Hp(9.45,0,2.5)
a(f'<ellipse cx="{mc[0]:.1f}" cy="{mc[1]:.1f}" rx="{px(0.42,mz)*0.92:.1f}" ry="{px(0.42,mz):.1f}" fill="#7a2a24" stroke="#e8d9a8" stroke-width="{px(0.06,mz):.1f}"/>')
a(poly(hq(door[0],door[1],DECK,3.3), fill="#7a3b2e"))
hz=Hxz(4.4,0)[1]
mx,my=Hp(4.65,0,2.6); a(f'<circle cx="{mx:.0f}" cy="{my:.0f}" r="{px(0.28,hz):.0f}" fill="#e9b52c"/>')
mx,my=Hp(4.15,0,2.0); a(f'<circle cx="{mx:.0f}" cy="{my:.0f}" r="{px(0.24,hz):.0f}" fill="#3f8f8a"/>')
a(poly(hq(4.8,4.0,1.3,1.5), fill="#c94a3a"))
a('</g>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.2" stroke-linejoin="round">')
a(poly(rend)); a(poly(hip)); a(poly(wall)); a(poly(roof)); a(poly(deckf))
for s0,s1 in wins:
  a(poly(hq(s0,s1,1.7,3.2), stroke=C["winframe"], stroke_width="5"))
  g=[seg(Hp(s1+(s0-s1)*k/3,0,3.2),Hp(s1+(s0-s1)*k/3,0,1.7)) for k in (1,2)]+[seg(Hp(s0,0,2.45),Hp(s1,0,2.45))]
  a(f'<path stroke="{C["winframe"]}" stroke-width="3" d="{" ".join(g)}"/>')
a(poly(hq(door[0],door[1],DECK,3.3)))
rl=[seg(Hp(HLEN+0.3,-1.0,1.8),Hp(-0.3,-1.0,1.8))]
s_=HLEN+0.3
while s_>=-0.31:
  rl.append(seg(Hp(s_,-1.0,0),Hp(s_,-1.0,1.8))); s_-=1.3
a(f'<path stroke="{C["rail"]}" stroke-width="6" d="{" ".join(rl)}"/>')
a('</g>')

# ---------- ピットハウス ----------
# 実物（Street View 2022）：屋根の上に黒い鉄骨の台（手すり付き）が載り、右へ張り出す。
# 台の上に銀色の箱・錆びた太い排気ダクト・黒い煙突。看板は台の左手前の端に立つ。
# 台を支えるのは側面の外に立つ黒い鉄骨の柱と X 字の筋交い。屋根の縁に回転式の換気口。
H18, H55 = WALL*(1-0.18), WALL*(1-0.55)
PS0, PS1, PT1, PH0, PH1 = -0.75, 6.1, SL+2.6, 3.85, 4.15     # 鉄骨の台（s の範囲・奥行き・高さ）
def zof(s,t): return Wxz(s,t)[1]
def tube(pts, d_m, col, z):
  d=f"M{pts[0][0]:.1f} {pts[0][1]:.1f} "+" ".join(f"Q{pts[i][0]:.1f} {pts[i][1]:.1f} {(pts[i][0]+pts[i+1][0])/2:.1f} {(pts[i][1]+pts[i+1][1])/2:.1f}" for i in range(1,len(pts)-1))+f" L{pts[-1][0]:.1f} {pts[-1][1]:.1f}"
  w=px(d_m,z)
  return f'<path d="{d}" fill="none" stroke="{C["ink"]}" stroke-width="{w+6:.1f}" stroke-linecap="butt"/><path d="{d}" fill="none" stroke="{col}" stroke-width="{w:.1f}" stroke-linecap="butt"/>'
# 煙（煙突の先から）
ch_b, ch_t = W(1.5,2.0,PH1), W(1.5,2.0,7.0); chz=zof(1.5,2.0)
a(f'<g filter="url(#wcs)"><ellipse cx="{ch_t[0]+60:.0f}" cy="{ch_t[1]-35:.0f}" rx="75" ry="34" fill="{C["smoke"]}" opacity="0.6"/><ellipse cx="{ch_t[0]+170:.0f}" cy="{ch_t[1]-70:.0f}" rx="95" ry="40" fill="{C["smoke"]}" opacity="0.45"/></g>')
# 壁・屋根の縁
eF=quadF(-0.3,FL+0.35,3.1,3.4,t=-0.3); eS=quadS(-0.3,SL+0.3,3.1,3.4,s=-0.3)
soffit=[W(-0.3,-0.3,3.1),W(FL+0.35,-0.3,3.1),W(FL,0,3.1),W(0,0,3.1),W(0,SL,3.1),W(-0.3,SL+0.3,3.1)]
a('<g filter="url(#wcs)">')
a(poly(quadF(0,FL,H18,WALL), fill="url(#rustp)")); a(poly(quadF(0,FL,H55,H18), fill=C["screen"])); a(poly(quadF(0,FL,0,H55), fill="url(#skirtp)"))
a(poly(quadS(0,SL,H18,WALL), fill="url(#rustp)")); a(poly(quadS(0,SL,H55,H18), fill=C["screen"], opacity="0.9")); a(poly(quadS(0,SL,0,H55), fill="url(#skirtSp)"))
a(poly(quadS(SL-0.95,SL-0.15,H55,2.4), fill=C["door"]))                       # 裏の赤いドア
a(poly(soffit, fill=C["rustd"], opacity="0.8"))
a('</g>')
# 波板の錆の筋と足元の影
st=[]
random.seed(31)
for _ in range(16):
  s_=random.uniform(0.3,FL-0.3); hh=random.uniform(0.3,0.9)
  st.append(poly([W(s_,0,H55-0.05),W(s_-0.12,0,H55-0.05),W(s_-0.1,0,H55-0.05-hh),W(s_-0.02,0,H55-0.05-hh)]))
a(f'<g filter="url(#wcs)" fill="{C["streak"]}" opacity="0.5">{"".join(st)}</g>')
a(f'<g filter="url(#wc)" opacity="{0.4 if not N else 0.35}">'+poly(quadF(0.2,FL-0.2,0,0.5), fill=C["shadow"])+poly(quadS(0.2,SL-0.2,0,0.6), fill=C["shadow"])+'</g>')
a(f'<g filter="url(#wcs)">{poly(eF, fill=C["metal"])}{poly(eS, fill=C["metal"])}</g>')
if N:
  a(poly(quadF(0.1,FL-0.1,H55+0.1,H18-0.1), fill="#e7a65a", opacity="0.45", filter="url(#glow)"))
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.6" stroke-linejoin="round">')
a(poly(quadF(0,FL,0,WALL))); a(poly(quadS(0,SL,0,WALL))); a(poly(eF)); a(poly(eS)); a(poly(quadS(SL-0.95,SL-0.15,H55,2.4)))
for h in (H18,H55): a(f'<path d="{seg(W(FL,0,h),W(0,0,h))} L{W(0,SL,h)[0]:.1f} {W(0,SL,h)[1]:.1f}"/>')
m=[seg(W(s,0,H18),W(s,0,H55)) for s in (0.9,1.9,2.9,3.9,4.9,5.8)]+[seg(W(0,t,H18),W(0,t,H55)) for t in (1.1,2.2)]
m.append(seg(W(FL,0,1.95),W(0,0,1.95))); m.append(seg(W(0,0,1.95),W(0,SL,1.95)))
a(f'<path stroke="{C["frame"]}" stroke-width="5" d="{" ".join(m)}"/>')
a('</g>')
# 回転式の換気口（屋根の縁の上、台の下）
tv=[]
for s_,t_ in ((2.7,0.25),(5.3,0.35)):
  z=zof(s_,t_); b=W(s_,t_,3.4); tp=W(s_,t_,3.8); w=px(0.5,z)
  tv.append(f'<rect x="{b[0]-w/2:.1f}" y="{tp[1]:.1f}" width="{w:.1f}" height="{b[1]-tp[1]:.1f}" fill="{C["metal"]}"/><ellipse cx="{tp[0]:.1f}" cy="{tp[1]:.1f}" rx="{w/2:.1f}" ry="{w/4:.1f}" fill="{C["metal"]}"/>'
            +"".join(f'<path d="M{b[0]-w/2+w*i/5:.1f} {tp[1]:.1f} L{b[0]-w/2+w*i/5:.1f} {b[1]:.1f}" stroke="{C["ink"]}" stroke-width="1.2"/>' for i in range(1,5)))
a(f'<g filter="url(#ink)" stroke="{C["ink"]}" stroke-width="2">{"".join(tv)}</g>')
# 鉄骨の台：下面（見上げなので見える）→ 前面・右側面
und=[W(PS0,0,PH0),W(PS1,0,PH0),W(PS1,PT1,PH0),W(PS0,PT1,PH0)]
pF=quadF(PS0,PS1,PH0,PH1,t=0.0); pS=quadS(0.0,PT1,PH0,PH1,s=PS0)
a(f'<g filter="url(#wcs)">{poly(und, fill=C["steel"], opacity="0.75")}{poly(pF, fill=C["steel"])}{poly(pS, fill=C["steel"])}</g>')
# 台の上：銀色の箱・黒い煙突・錆びたダクト
bxF=quadF(1.9,3.4,PH1,5.4,t=0.7); bxS=quadS(0.7,2.2,PH1,5.4,s=1.9)
a(f'<g filter="url(#wcs)">{poly(bxS, fill=C["galvd"])}{poly(bxF, fill=C["galv"])}</g><g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.2">{poly(bxF)}{poly(bxS)}</g>')
a('<g filter="url(#ink)">'+tube([ch_b,ch_t], 0.6, C["steel"], chz)+'</g>')
# 錆びた太いダクト：箱の上から立ち上がり、手前に曲がって台の前の縁へ下りる
duct=[W(2.7,1.4,5.4),W(2.7,1.4,6.0),W(2.0,0.9,6.25),W(1.0,0.45,5.8),W(0.7,0.35,4.9),W(0.7,0.35,PH1)]
a('<g filter="url(#ink)">'+tube(duct, 0.45, C["pipe"], zof(1.8,0.9))+'</g>')
# 手すり（台の前の縁と右の縁）
rl=[seg(W(PS0,0.05,4.95),W(PS1,0.05,4.95)), seg(W(PS0,0.05,4.55),W(PS1,0.05,4.55)),
    seg(W(PS0,0.05,4.95),W(PS0,PT1,4.95)), seg(W(PS0,0.05,4.55),W(PS0,PT1,4.55))]
s_=PS0
while s_<=PS1: rl.append(seg(W(s_,0.05,PH1),W(s_,0.05,4.95))); s_+=0.9
t_=0.05
while t_<=PT1: rl.append(seg(W(PS0,t_,PH1),W(PS0,t_,4.95))); t_+=0.9
a(f'<g filter="url(#ink)" fill="none" stroke="{C["steel"]}" stroke-width="3">{"".join(f"<path d=\"{d}\"/>" for d in rl)}</g>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.4">{poly(pF)}{poly(pS)}</g>')
# 看板：台の左手前の端。BBQ は1文字ずつ黒い枠に入る
def plane_text(sc, h, cap_m, body, t=0.0):
  c=W(sc,t,h); p0=W(sc+1,t,h); p1=W(sc-1,t,h); Zc=zof(sc,t)
  dx=(p1[0]-p0[0])/2; dy=(p1[1]-p0[1])/2; k=D/Zc
  size=k*cap_m/0.73
  return f'<g transform="translate({c[0]:.1f},{c[1]:.1f}) matrix({dx/k:.4f},{dy/k:.4f},0,1,0,0)">'+body.format(size=f"{size:.1f}")+'</g>'
LT=[("B",5.7),("B",4.95),("Q",4.2)]
boxes="".join(poly(quadF(sc-0.36,sc+0.36,PH1,5.25,t=-0.05)) for _,sc in LT)
bar=quadF(3.75,6.15,5.4,5.85,t=-0.05)
a(f'<g filter="url(#wcs)" fill="{C["signbox"]}">{boxes}{poly(bar)}</g><g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2">{boxes}{poly(bar)}</g>')
ty='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" letter-spacing="1" fill="'+C["ty"]+'" stroke="'+C["ink"]+'" stroke-width="1.2">TERRY BLACK’S</text>'
def L(ch, fill, stroke, sw): return '<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" fill="'+fill+'" stroke="'+stroke+'" stroke-width="'+str(sw)+'">'+ch+'</text>'
if N:
  glow="".join(plane_text(sc,4.33,0.72,L(ch,"#ff5a20","#ff7a30",16),t=-0.06) for ch,sc in LT)+plane_text(4.95,5.5,0.3,'<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" letter-spacing="1" fill="#ffcf5a" stroke="#ffcf5a" stroke-width="8">TERRY BLACK’S</text>',t=-0.06)
  a(f'<g filter="url(#glow2)" opacity="0.9">{glow}</g>')
a(plane_text(4.95,5.5,0.3,ty,t=-0.06))
for ch,sc in LT: a(plane_text(sc,4.33,0.72,L(ch,C["bboq"],"#fff1d0",3),t=-0.06))
# NO OFFSITE ALCOHOL（正面の角寄り、網戸の上）
na=quadF(0.35,1.0,1.75,2.6,t=-0.02)
a(f'<g filter="url(#wcs)">{poly(na, fill="#f4f1ea")}</g><g filter="url(#ink)" fill="none" stroke="#c0322b" stroke-width="2.5">{poly(na)}</g>')
for i,txt in enumerate(("NO OFFSITE","ALCOHOL","ALLOWED")):
  a(plane_text(0.67,2.42-i*0.22,0.075,'<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="{size}" fill="#c0322b">'+txt+'</text>',t=-0.03))
# 角の木の見切り・黒い鉄骨の柱と X 字の筋交い・ボラード・コーン
trim=[(W(0,0,0),W(0,0,3.1),zof(0,0))]
pr="".join(f'<rect x="{b[0]-px(0.07,z):.1f}" y="{t[1]:.1f}" width="{px(0.14,z):.1f}" height="{b[1]-t[1]:.1f}"/>' for b,t,z in trim)
sp=[]
for t_ in (0.0, SL+0.3, PT1):
  z=zof(PS0,t_); b=W(PS0,t_,0); tp=W(PS0,t_,PH0); w=px(0.2,z)
  sp.append(f'<rect x="{b[0]-w/2:.1f}" y="{tp[1]:.1f}" width="{w:.1f}" height="{b[1]-tp[1]:.1f}"/>')
xb=[seg(W(PS0,0.0,0.9),W(PS0,SL+0.3,PH0)), seg(W(PS0,0.0,PH0),W(PS0,SL+0.3,0.9))]
a(f'<g filter="url(#wcs)" fill="{C["rail"]}">{pr}</g>')
bol=[]
for s,t in ((0.9,-0.4),(3.2,-0.4),(-0.35,0.9),(-0.35,1.9),(-0.35,2.9)):
  X,Z=Wxz(s,t); b=G(X,Z,0); tp=G(X,Z,1.0); w=px(0.22,Z)
  bol.append(f'<rect x="{b[0]-w/2:.1f}" y="{tp[1]:.1f}" width="{w:.1f}" height="{b[1]-tp[1]:.1f}" rx="{w/3:.1f}"/>')
a(f'<g filter="url(#wcs)" fill="{C["yellow"]}">{"".join(bol)}</g>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2">{pr}{"".join(bol)}</g>')
a(f'<g filter="url(#ink)" fill="{C["steel"]}" stroke="{C["ink"]}" stroke-width="1.5">{"".join(sp)}</g><g filter="url(#ink)" fill="none" stroke="{C["steel"]}" stroke-width="{px(0.14,zof(PS0,1.6)):.1f}">{"".join(f"<path d=\"{d}\"/>" for d in xb)}</g>')
cones=[]
for s,t in ((-1.3,1.4),(-1.5,2.5),(-1.1,3.6)):
  X,Z=Wxz(s,t); b=G(X,Z,0); tp=G(X,Z,0.75); w=px(0.36,Z); bw=px(0.5,Z)
  cones.append(f'<polygon points="{b[0]-w/2:.1f},{b[1]:.1f} {b[0]+w/2:.1f},{b[1]:.1f} {tp[0]:.1f},{tp[1]:.1f}" fill="#f0662c"/><rect x="{b[0]-bw/2:.1f}" y="{b[1]-px(0.06,Z):.1f}" width="{bw:.1f}" height="{px(0.06,Z):.1f}" fill="#3a3a38"/>'
               f'<polygon points="{b[0]-w*0.32:.1f},{b[1]-(b[1]-tp[1])*0.35:.1f} {b[0]+w*0.32:.1f},{b[1]-(b[1]-tp[1])*0.35:.1f} {b[0]+w*0.22:.1f},{b[1]-(b[1]-tp[1])*0.55:.1f} {b[0]-w*0.22:.1f},{b[1]-(b[1]-tp[1])*0.55:.1f}" fill="#f6f5f0"/>')
a(f'<g filter="url(#ink)" stroke="{C["ink"]}" stroke-width="1.5">{"".join(cones)}</g>')

# ---------- 手前の小物（車止めブロック・標識） ----------
cs=[]
for sc in (7.65, 4.95, 2.25):
  cs.append(poly([Hp(sc+0.9,-2.0,0.15),Hp(sc-0.9,-2.0,0.15),Hp(sc-0.9,-2.0,0),Hp(sc+0.9,-2.0,0)]))
a(f'<g filter="url(#wcs)" fill="{C["yellow"]}">{"".join(cs)}</g>')
sb,stp=G(-6.0,21.0,0),G(-6.0,21.0,2.1); sw_=px(0.45,21.0)
a(f'<g filter="url(#ink)" stroke="{C["ink"]}" stroke-width="2.4"><path d="{seg(sb,stp)}"/><rect x="{stp[0]-sw_/2:.1f}" y="{stp[1]-sw_*1.1:.1f}" width="{sw_:.1f}" height="{sw_*1.1:.1f}" fill="{C["sign"]}"/></g>')
# 街灯（夜）：家とピットハウスの間、少し手前
if N:
  lx,ly_=G(-2.9,21.0,4.2)
  pb=G(-2.9,21.0,0)
  a(f'<path d="{seg(pb,(lx,ly_))}" stroke="#05070c" stroke-width="5"/>')
  a(f'<circle cx="{lx:.0f}" cy="{ly_:.0f}" r="70" fill="#6fa8ff" filter="url(#glow2)" opacity="0.9"/>')
  rays="".join(f'<path d="M{lx:.0f} {ly_:.0f} L{lx+math.cos(math.radians(t))*L:.0f} {ly_+math.sin(math.radians(t))*L:.0f}"/>' for t,L in [(200,420),(-35,380),(20,180),(160,200),(-90,160),(250,260),(290,150)])
  a(f'<g stroke="#9cc4ff" stroke-width="3" opacity="0.6" filter="url(#ink)">{rays}</g><circle cx="{lx:.0f}" cy="{ly_:.0f}" r="9" fill="#ffffff"/>')

# ---------- 帯（手前の区画線が下を通るので地色で薄く下敷き） ----------
a(f'<rect x="640" y="1212" width="880" height="86" fill="{C["bg"]}" opacity="0.6" filter="url(#wcs)"/>')
a(f'<g filter="url(#ink)" stroke="{C["title"]}" stroke-width="2.2"><path d="M660 1218 L1500 1218 M660 1291 L1500 1291"/></g>')
a(f'<text x="1080" y="1268" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="40" letter-spacing="8" fill="{C["sub"]}">BRISKET SAUSAGE &amp; RIBS</text>')
a('</svg>')
open(out,"w").write("\n".join(o))
