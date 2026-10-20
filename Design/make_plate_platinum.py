# Face1_platinum: makes RC*Platinum assets from Design/RedClip-faceplate-platinum.png (copy it next to this as plat.png).
# Face1_platinum: same layout as Face1 (red), silver finish. Same erase-the-moving-parts idea,
# but text/pointers can be dark-on-light, so masks use local contrast instead of "light pixels".
import cv2, numpy as np
src='plat.png'
im=cv2.imread(src); H,W=im.shape[:2]
hsv=cv2.cvtColor(im,cv2.COLOR_BGR2HSV); V=hsv[...,2]; S=hsv[...,1].astype(int)
Vb=cv2.medianBlur(V,21).astype(int); Vi=V.astype(int)
contrast=np.abs(Vi-Vb)>28
mask=np.zeros((H,W),np.uint8)
def add(m,dil=2):
    global mask
    if dil: m=cv2.dilate(m,np.ones((dil*2+1,dil*2+1),np.uint8))
    mask|=m
def rect(x0,y0,x1,y1,cond):
    m=np.zeros((H,W),np.uint8); m[y0:y1,x0:x1]=cond[y0:y1,x0:x1].astype(np.uint8)*255; return m
big=[(208.9,581.5),(465.4,581.5),(723.4,581.4),(983.1,581.0),(1240.8,581.8)]
small=[(198.1,795.8),(677.6,796.6)]
yy,xx=np.ogrid[:H,:W]
for (cx,cy),r in [(c,56) for c in big]+[(c,31) for c in small]:
    inside=((xx-cx)**2+(yy-cy)**2)<r*r
    add((inside&(Vi<Vb-45)).astype(np.uint8)*255,2)      # dark pointer on the silver cap
for cx,cy in big: add(rect(int(cx-60),676,int(cx+60),704,contrast),2)
for cx,cy in small: add(rect(int(cx-32),846,int(cx+32),868,contrast),2)
add(rect(580,36,870,70,contrast),2)                       # preset name
add(rect(690,404,782,454,(V>60)),2)                       # CLIP digits
add(rect(312,132,1180,388,(S>110)&(V>90)),2)              # screen dashes + ceiling label
add(rect(972,36,1002,72,contrast|(S>70)),2)               # A (red letter)
add(rect(1030,38,1056,70,contrast),2)                     # B
add(rect(1196,34,1230,74,contrast|(S>70)),2)              # ? (red glyph)
cells={'redModern':(282,758,387,791),'redClassic':(387,758,490,791),'unity':(312,808,464,843),
 'boxFlat':(820,792,912,832),'boxModern':(912,792,1013,832),'boxClassic':(1013,792,1116,832),
 'delta':(1180,794,1313,834),'clipHard':(123,922,243,968),'clipClassic':(243,922,363,968),'clipModern':(363,922,486,968),
 'link':(567,908,690,958),'os1':(767,922,877,966),'os2':(877,922,982,966),'os4':(982,922,1093,966),'bypass':(1162,907,1327,958)}
for k,(x0,y0,x1,y1) in cells.items():
    reg=V[y0:y1,x0:x1]; bl=cv2.medianBlur(reg,21).astype(int); diff=np.abs(reg.astype(int)-bl)>30
    band=np.zeros_like(diff); band[6:-6,6:-6]=diff[6:-6,6:-6]
    if k=='bypass': band[:, :45]=False
    m=np.zeros((H,W),np.uint8); m[y0:y1,x0:x1]=band.astype(np.uint8)*255; add(m,2)
add((((xx-1194)**2+(yy-932)**2)<11**2).astype(np.uint8)*255,1)    # bypass LED
for x0,y0,x1,y1 in [(80,1018,162,1046),(600,1020,770,1048),(786,1024,806,1044),(1262,1018,1370,1046)]:
    add(rect(x0,y0,x1,y1,contrast),2)
clean=cv2.inpaint(im,mask,5,cv2.INPAINT_TELEA)
m=np.zeros((H,W),np.uint8); m[130:170,1022:1176]=255
clean=cv2.inpaint(clean,m,9,cv2.INPAINT_TELEA)
rng=np.random.default_rng(3); c=clean.astype(np.float32)
def rowfill(x0,y0,x1,y1,edge=6):
    for y in range(y0,y1):
        left=c[y,x0-edge:x0].mean(axis=0); right=c[y,x1:x1+edge].mean(axis=0)
        t=np.linspace(0,1,x1-x0)[:,None]; c[y,x0:x1]=left*(1-t)+right*t
    n=rng.normal(0,1,(y1-y0,x1-x0)).astype(np.float32)
    n=cv2.GaussianBlur(n,(0,0),sigmaX=9,sigmaY=0.4)*9
    lum=c[y0:y1,x0:x1].mean(axis=2,keepdims=True)/255
    c[y0:y1,x0:x1]+=n[...,None]*lum*1.2          # neutral grain for silver
for cx,cy in big: rowfill(int(cx-62),674,int(cx+62),706)
for cx,cy in small: rowfill(int(cx-34),845,int(cx+34),869)
out=np.clip(c,0,255).astype(np.uint8); cv2.imwrite('out/plat_clean.png',out)
from PIL import Image
a=Image.open('out/plat_clean.png').convert('RGB')
a.crop((0,0,1448,997)).save('out/RCPlatePlatinum.png')
a.crop((0,997,1448,1086)).save('out/RCStripPlatinum.png')
a.crop((876,921,982,967)).save('out/RCSegLitPlatinum.png')
a.crop((244,921,362,969)).save('out/RCSegOffPlatinum.png')
a.crop((958,28,1015,79)).save('out/RCABLitPlatinum.png')
a.crop((1015,28,1072,79)).save('out/RCABOffPlatinum.png')
a.crop((40,0,1410,1086)).save('out/plat_preview.png')
