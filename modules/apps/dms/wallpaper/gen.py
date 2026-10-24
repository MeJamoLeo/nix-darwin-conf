# Terry Black's（オースティンの BBQ 屋）の手描き風壁紙を SVG で吐く生成スクリプト。
# 使い方: python3 gen.py day|night out.svg   （day = DMS の light モード用、night = dark モード用）
# 本物の店の写真（昼・夜）と手持ちの T シャツの雰囲気を参考に Claude が描いた（2026-10-24）。
# 構図は1つで、色（C の辞書）と夜だけの要素（星・ネオンの光・街灯）が変わる。
# 建物は2点透視：F() が正面（左奥の消失点 VPL へ）、Sd() が側面（右奥の VPR へ）。
# f は壁の上端 0 〜 下端 1 の高さの割合。PNG 化は ../home.nix の nix ビルドで行う。
import math, sys, random
mode = sys.argv[1]; out = sys.argv[2]
N = mode == "night"
C = dict(
  bg="#f3eee2", ink="#25272a", title="#25272a", sub="#3d7a37",
  sky="#cfe3ee", t1="#8fc274", t2="#7db863", t3="#6dab57", t4="#5f9e4c", tdark="#4a893c", tlight="#a4d088",
  rust="#9a5b34", rustd="#7a4426", screen="#4a3d2f", frame="#c9b48a", skirt="#ecebe4", skirtl="#c9cac4",
  skirtS="#d7d7d0", skirtSl="#b5b6b0", roof="#3b342d", house="#dccaa4", housel="#c4b088", shingle="#8f8e88",
  win="#3c4650", winframe="#f4f1e8", rail="#7a5a3c", stone="#b9b6ad", yellow="#e9b52c", ground="#d8d2c3",
  smoke="#c9cbcb", bboq="#e8572a", ty="#f2b632", sign="#2f6fb0", line="#f4f1e8")
if N:
  C.update(bg="#0e1422", ink="#05070c", title="#f3eee2", sub="#8fc274", sky="#0e1422",
  t1="#1f3a2e", t2="#1a3228", t3="#183026", t4="#14281f", tdark="#0f1f18", tlight="#24443a",
  rust="#4a3426", rustd="#3a281d", screen="#2b4f86", frame="#5a4a36", skirt="#a9b6cc", skirtl="#8592a8",
  skirtS="#7f8aa0", skirtSl="#667087", roof="#141820", house="#5b5446", housel="#4a4438", shingle="#353a44",
  win="#e7a65a", winframe="#9a9a92", rail="#3a2c20", stone="#4a4c52", yellow="#c99a24", ground="#1b2130",
  smoke="#3a4252", line="#c8ccd4")
VPL=(-4200.0,860.0); VPR=(2650.0,860.0)
CX, CT, CB = 1440.0, 800.0, 1110.0
def ly(x,y0,vp): return y0+(vp[1]-y0)*(x-CX)/(vp[0]-CX)
def F(x,f):
  t=ly(x,CT,VPL); b=ly(x,CB,VPL); return (x,t+(b-t)*f)
def Sd(x,f):
  t=ly(x,CT,VPR); b=ly(x,CB,VPR); return (x,t+(b-t)*f)
def P(*p): return " ".join(f"{x:.1f},{y:.1f}" for x,y in p)
FX0, SX1 = 940.0, 1585.0
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
# trees
random.seed(4)
cl=[(700,660,230,170,"t1"),(950,560,250,170,"t2"),(1230,520,260,170,"t3"),(1500,560,240,170,"t2"),(1700,700,200,160,"t1"),(560,780,160,120,"t2"),(1800,840,140,110,"t4"),
    (850,690,170,90,"tdark"),(1350,640,190,100,"tdark"),(1100,450,130,70,"tlight"),(1600,520,120,70,"tlight")]
a('<g filter="url(#wc)">'+"".join(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{C[c]}" opacity="{0.8 if c=="tdark" else 1}"/>' for x,y,rx,ry,c in cl)+'</g>')
segs=[]
for _ in range(80):
  x0,y0,rx,ry,_c=random.choice(cl[:7]); t=random.uniform(0,2*math.pi); x=x0+rx*math.cos(t); y=y0+ry*math.sin(t)
  if y>800: continue
  segs.append(f"M{x:.0f} {y:.0f} q8 -10 18 -2")
a(f'<g filter="url(#ink)" fill="none" stroke="{"#2f4a2a" if not N else "#0a1410"}" stroke-width="2" stroke-linecap="round"><path d="{" ".join(segs)}"/><path d="M700 820 q-20 -80 -70 -130 M710 760 q30 -60 20 -120 M1700 820 q10 -90 70 -150 M1740 740 q-40 -50 -30 -110"/></g>')
# stone wall right
a(f'<polygon filter="url(#wc)" fill="{C["stone"]}" points="1560,930 1800,900 1810,1085 1560,1095"/>')
st=[]
random.seed(9)
for r in range(5):
  for c in range(6):
    x=1580+c*38+(r%2)*18; y=940+r*30
    if x<1790: st.append(f'<ellipse cx="{x}" cy="{y}" rx="17" ry="12"/>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="1.6" opacity="0.7">{"".join(st)}</g>')
# ground
a(f'<polygon filter="url(#wc)" opacity="0.75" fill="{C["ground"]}" points="380,1060 1820,1060 1900,1190 300,1190"/>')
# --- left house ---
hb, ht = 1068.0, 905.0
def H(x,f):
  t=ht+(VPL[1]-ht)*(x-960)/(VPL[0]-960); b=hb+(VPL[1]-hb)*(x-960)/(VPL[0]-960); return (x,t+(b-t)*f)
roof=[(470,H(470,0)[1]+6),(985,H(985,0)[1]+6),(905,820),(575,815)]
a('<g filter="url(#wcs)">')
a(f'<polygon points="{P(H(500,0),H(960,0),H(960,1),H(500,1))}" fill="url(#sidingp)"/>')
a(f'<polygon points="{P(*roof)}" fill="url(#shinglep)"/>')
wins=[(530,590),(610,670),(800,860)]
for x0,x1 in wins:
  a(f'<polygon points="{P(H(x0,.22),H(x1,.22),H(x1,.62),H(x0,.62))}" fill="{C["win"]}"/>')
a(f'<polygon points="{P(H(700,.18),H(775,.18),H(775,1),H(700,1))}" fill="#7a3b2e"/>')
a(f'<circle cx="725" cy="975" r="16" fill="#e9b52c"/><circle cx="750" cy="1010" r="14" fill="#3f8f8a"/><rect x="708" y="1025" width="50" height="12" fill="#c94a3a"/>')
a('</g>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.4" stroke-linejoin="round">')
a(f'<polygon points="{P(H(500,0),H(960,0),H(960,1),H(500,1))}"/><polygon points="{P(*roof)}"/>')
for x0,x1 in wins:
  a(f'<polygon stroke="{C["winframe"]}" stroke-width="6" points="{P(H(x0,.22),H(x1,.22),H(x1,.62),H(x0,.62))}"/>')
  m=(x0+x1)/2; p,q=H(m,.22),H(m,.62); a(f'<path stroke="{C["winframe"]}" stroke-width="4" d="M{m} {p[1]:.1f} L{m} {q[1]:.1f}"/>')
a(f'<polygon points="{P(H(700,.18),H(775,.18),H(775,1),H(700,1))}"/>')
# porch rail
r0,r1=H(500,.68),H(940,.68); a(f'<path stroke="{C["rail"]}" stroke-width="7" d="M{r0[0]} {r0[1]+40:.1f} L{r1[0]} {r1[1]+40:.1f}"/>')
for x in range(520,941,70):
  p=H(x,1); a(f'<path stroke="{C["rail"]}" stroke-width="7" d="M{x} {p[1]+40:.1f} L{x} {p[1]-60+40:.1f}"/>')
a(f'<path d="M870 1135 L870 1050"/><rect x="852" y="1015" width="36" height="40" fill="{C["sign"]}"/>')
a('</g>')
# --- main pit house ---
# vent + stack behind
a(f'<g filter="url(#wcs)"><ellipse cx="1420" cy="470" rx="80" ry="40" fill="{C["smoke"]}" opacity="0.6"/><ellipse cx="1480" cy="410" rx="95" ry="45" fill="{C["smoke"]}" opacity="0.5"/>'
  f'<rect x="1040" y="560" width="12" height="180" fill="{C["rustd"]}"/><rect x="1020" y="520" width="52" height="70" rx="8" fill="{"#b1b4b6" if not N else "#4a505c"}"/></g>')
a(f'<g filter="url(#ink)" fill="none" stroke-linecap="round"><path d="M1395 790 L1395 600 Q1395 540 1455 520" stroke="{C["ink"]}" stroke-width="40"/><path d="M1395 790 L1395 600 Q1395 540 1455 520" stroke="{C["rust"]}" stroke-width="32"/>'
  f'<path d="M1350 790 L1350 650" stroke="{C["ink"]}" stroke-width="28"/><path d="M1350 790 L1350 650" stroke="{C["rustd"]}" stroke-width="21"/>'
  f'<rect x="1020" y="520" width="52" height="70" rx="8" stroke="{C["ink"]}" stroke-width="2.4"/><path d="M1046 590 L1046 740" stroke="{C["ink"]}" stroke-width="2.4"/>'
  f'<path stroke="{"#6f7478" if not N else "#556070"}" stroke-width="2" d="M1460 515 c25 -25 0 -50 40 -70 c30 -15 25 -45 60 -60"/></g>')
# roof frame
rf=[F(930,-.16),F(CX+10,-.16),Sd(SX1+10,-.16),Sd(SX1+10,0),F(CX+10,0),F(930,0)]
truss=[F(1000,-.16),(1110,F(1110,-.16)[1]-70),(1330,F(1330,-.16)[1]-70),F(1400,-.16)]
a('<g filter="url(#wcs)">')
a(f'<polygon points="{P(*truss)}" fill="{C["roof"]}"/>')
a(f'<polygon points="{P(*rf)}" fill="url(#rustp)"/>')
a(f'<polygon points="{P(F(FX0,0),F(CX,0),F(CX,.18),F(FX0,.18))}" fill="url(#rustp)"/>')
a(f'<polygon points="{P(F(FX0,.18),F(CX,.18),F(CX,.55),F(FX0,.55))}" fill="{C["screen"]}"/>')
a(f'<polygon points="{P(F(FX0,.55),F(CX,.55),F(CX,1),F(FX0,1))}" fill="url(#skirtp)"/>')
a(f'<polygon points="{P(Sd(CX,0),Sd(SX1,0),Sd(SX1,.18),Sd(CX,.18))}" fill="url(#rustp)"/>')
a(f'<polygon points="{P(Sd(CX,.18),Sd(SX1,.18),Sd(SX1,.55),Sd(CX,.55))}" fill="{C["screen"]}" opacity="0.9"/>')
a(f'<polygon points="{P(Sd(CX,.55),Sd(SX1,.55),Sd(SX1,1),Sd(CX,1))}" fill="url(#skirtSp)"/>')
a('</g>')
if N:  # interior glow
  a(f'<polygon filter="url(#glow)" fill="#6fa8ff" opacity="0.55" points="{P(F(FX0,.2),F(CX,.2),F(CX,.53),F(FX0,.53))}"/>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2.6" stroke-linejoin="round">')
a(f'<polygon points="{P(*truss)}"/><polygon points="{P(*rf)}"/>')
a(f'<polygon points="{P(F(FX0,0),F(CX,0),F(CX,1),F(FX0,1))}"/><polygon points="{P(Sd(CX,0),Sd(SX1,0),Sd(SX1,1),Sd(CX,1))}"/>')
for f in (.18,.55):
  p,q,r=F(FX0,f),F(CX,f),Sd(SX1,f); a(f'<path d="M{p[0]:.1f} {p[1]:.1f} L{q[0]:.1f} {q[1]:.1f} L{r[0]:.1f} {r[1]:.1f}"/>')
m=[]
for x in (1035,1135,1240,1340):
  p,q=F(x,.18),F(x,.55); m.append(f"M{x} {p[1]:.1f} L{x} {q[1]:.1f}")
for x in (1500,):
  p,q=Sd(x,.18),Sd(x,.55); m.append(f"M{x} {p[1]:.1f} L{x} {q[1]:.1f}")
p,q=F(FX0,.36),F(CX,.36); m.append(f"M{p[0]:.1f} {p[1]:.1f} L{q[0]:.1f} {q[1]:.1f}")
a(f'<path stroke="{C["frame"]}" stroke-width="7" d="{" ".join(m)}"/>')
# truss struts
s=[]
for x in (1040,1110,1180,1250,1320,1370):
  p=F(x,-.16); s.append(f"M{x} {p[1]:.1f} L{x+30} {p[1]-60:.1f}")
a(f'<path stroke-width="2" d="{" ".join(s)}"/>')
a('</g>')
# sign letters
def ang(f):
  p,q=F(1050,f),F(1350,f); return math.degrees(math.atan2(q[1]-p[1],q[0]-p[0]))
def T(cx,cy,ag,body): return f'<g transform="translate({cx:.1f},{cy:.1f}) skewY({ag:.2f})">{body}</g>'
c1=F(1205,-.62); c2=F(1205,-.25)
ty=f'<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="40" letter-spacing="2" fill="{C["ty"]}" stroke="{C["ink"]}" stroke-width="1.6">TERRY BLACK’S</text>'
bq_o='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="120" letter-spacing="10" fill="none" stroke="#1b1612" stroke-width="16" stroke-linejoin="round">BBQ</text>'
bq=f'<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="120" letter-spacing="10" fill="{C["bboq"]}" stroke="#fff1d0" stroke-width="3.5">BBQ</text>'
if N:
  gb='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="120" letter-spacing="10" fill="#ff5a20" stroke="#ff7a30" stroke-width="18">BBQ</text>'
  gt='<text x="0" y="0" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="40" letter-spacing="2" fill="#ffcf5a" stroke="#ffcf5a" stroke-width="10">TERRY BLACK’S</text>'
  a('<g filter="url(#glow2)" opacity="0.9">'+T(*c2,ang(-.25),gb)+T(*c1,ang(-.62),gt)+'</g>')
a(T(*c1,ang(-.62),ty)); a(T(*c2,ang(-.25),bq_o+bq))
# posts + bollards
p0,p1=F(CX,-.16),F(CX,1); q0,q1=Sd(SX1,-.16),Sd(SX1,1)
a(f'<g filter="url(#wcs)" fill="{C["rail"]}"><rect x="{CX-8}" y="{p0[1]:.1f}" width="16" height="{p1[1]-p0[1]:.1f}"/><rect x="{SX1-7}" y="{q0[1]:.1f}" width="14" height="{q1[1]-q0[1]:.1f}"/></g>')
bol=[]
for pt in (F(1415,1.05),Sd(1470,1.05),Sd(1530,1.04),Sd(1590,1.03)):
  bol.append(f'<rect x="{pt[0]-8:.1f}" y="{pt[1]-95:.1f}" width="16" height="95" rx="5"/>')
a(f'<g filter="url(#wcs)" fill="{C["yellow"]}">'+"".join(bol)+'</g>')
a(f'<g filter="url(#ink)" fill="none" stroke="{C["ink"]}" stroke-width="2">'+"".join(bol)+f'<rect x="{CX-8}" y="{p0[1]:.1f}" width="16" height="{p1[1]-p0[1]:.1f}"/><rect x="{SX1-7}" y="{q0[1]:.1f}" width="14" height="{q1[1]-q0[1]:.1f}"/></g>')
# lamp (night)
if N:
  lx,ly_=985,860
  a(f'<circle cx="{lx}" cy="{ly_}" r="70" fill="#6fa8ff" filter="url(#glow2)" opacity="0.9"/>')
  rays="".join(f'<path d="M{lx} {ly_} L{lx+math.cos(math.radians(t))*L:.0f} {ly_+math.sin(math.radians(t))*L:.0f}"/>' for t,L in [(200,420),(-35,380),(20,180),(160,200),(-90,160),(250,260),(290,150)])
  a(f'<g stroke="#9cc4ff" stroke-width="3" opacity="0.6" filter="url(#ink)">{rays}</g><circle cx="{lx}" cy="{ly_}" r="9" fill="#ffffff"/>')
# parking
a(f'<g filter="url(#wcs)" fill="{C["line"]}" opacity="0.9">')
for i,x in enumerate((560,720,880,1040,1200)):
  a(f'<polygon points="{x},1150 {x+10},1150 {x-50},1215 {x-62},1215"/>')
a(f'<polygon points="430,1148 1300,1148 1300,1156 430,1156"/></g>')
a(f'<g filter="url(#wcs)" fill="{C["yellow"]}"><rect x="600" y="1100" width="130" height="18" rx="4"/><rect x="390" y="1092" width="110" height="16" rx="4"/></g>')
a(f'<g filter="url(#ink)" stroke="{C["title"]}" stroke-width="2.2"><path d="M660 1218 L1500 1218 M660 1291 L1500 1291"/></g>')
a(f'<text x="1080" y="1268" text-anchor="middle" font-family="DejaVu Sans" font-weight="700" font-size="40" letter-spacing="8" fill="{C["sub"]}">BRISKET SAUSAGE &amp; RIBS</text>')
a('</svg>')
open(out,"w").write("\n".join(o))
