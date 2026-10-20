# Makes RCPlate / RCStrip / RCSeg* / RCAB* from Design/RedClip-faceplate.png (copy it next to this script as face.png;
# writes into out/). Erases every moving part so the app can draw them live in the same places.
import cv2, numpy as np, json
im=cv2.imread('face.png'); H,W=im.shape[:2]
hsv=cv2.cvtColor(im,cv2.COLOR_BGR2HSV); V=hsv[...,2].astype(int); S=hsv[...,1].astype(int)
mask=np.zeros((H,W),np.uint8)
def add(m, dil=2):
    global mask
    if dil: m=cv2.dilate(m,np.ones((dil*2+1,dil*2+1),np.uint8))
    mask|=m
def rectmask(x0,y0,x1,y1,cond):
    m=np.zeros((H,W),np.uint8); sub=cond[y0:y1,x0:x1]; m[y0:y1,x0:x1]=sub.astype(np.uint8)*255; return m
light=(V>150)&(S<90)          # white / cream text and pointers
reddish=(S>110)&(V>90)

big=[(208.9,581.5),(465.4,581.5),(723.4,581.4),(983.1,581.0),(1240.8,581.8)]
small=[(198.1,795.8),(677.6,796.6)]
# knob pointers: light pixels inside the cap
for (cx,cy),r in [(c,56) for c in big]+[(c,31) for c in small]:
    yy,xx=np.ogrid[:H,:W]; inside=((xx-cx)**2+(yy-cy)**2)<r*r
    add((inside&(V>165)&(S<70)).astype(np.uint8)*255,2)
# values under the knobs
for cx,cy in big: add(rectmask(int(cx-60),676,int(cx+60),704,light),2)
for cx,cy in small: add(rectmask(int(cx-32),846,int(cx+32),868,light),2)
# preset name
add(rectmask(580,36,870,70,light),2)
# CLIP digits (red glow) -> keep "CLIP" and "dB"
add(rectmask(690,404,782,454,(V>60)),2)
# screen: red dashes and the CEILING label inside the plot
add(rectmask(312,132,1180,388,reddish),2)
# A / B letters, ? glyph
add(rectmask(974,38,1000,70,(V>110)),2)   # A letter only
add(rectmask(1016,32,1070,76,light),2)    # B
add(rectmask(1198,35,1228,73,(V>110)&(S>80)),2)   # ? glyph only
# segment + button labels
cells={'redModern':(282,758,387,791),'redClassic':(387,758,490,791),
 'unity':(312,808,464,843),
 'boxFlat':(820,792,912,832),'boxModern':(912,792,1013,832),'boxClassic':(1013,792,1116,832),
 'delta':(1180,794,1313,834),
 'clipHard':(123,922,243,968),'clipClassic':(243,922,363,968),'clipModern':(363,922,486,968),
 'link':(567,908,690,958),
 'os1':(767,922,877,966),'os2':(877,922,982,966),'os4':(982,922,1093,966),
 'bypass':(1162,907,1327,958)}
for k,(x0,y0,x1,y1) in cells.items():
    reg=im[y0:y1,x0:x1]; g=cv2.cvtColor(reg,cv2.COLOR_BGR2HSV)[...,2].astype(int)
    bl=cv2.medianBlur(cv2.cvtColor(reg,cv2.COLOR_BGR2HSV)[...,2],21).astype(int)
    diff=np.abs(g-bl)>30
    # only the middle band (text), not the cell edges
    m=np.zeros((H,W),np.uint8); band=np.zeros_like(diff); bx=6; by=6
    band[by:-by,bx:-bx]=diff[by:-by,bx:-bx]
    if k=='bypass': band[:, :45]=False     # keep the LED dot area separately
    m[y0:y1,x0:x1]=band.astype(np.uint8)*255
    add(m,2)
# bypass LED dot (redrawn at runtime)
yy,xx=np.ogrid[:H,:W]; add((((xx-1194)**2+(yy-932)**2)<11**2).astype(np.uint8)*255,1)
# transport strip: PLAY icon+text, file name, progress dot, EXPORT icon+text
add(rectmask(80,1018,162,1046,(V>60)),2)
add(rectmask(600,1020,770,1048,(V>45)),2)
add(rectmask(786,1024,806,1044,(V>45)),2)
add(rectmask(1262,1018,1370,1046,(V>60)),2)
clean=cv2.inpaint(im,mask,5,cv2.INPAINT_TELEA)
cv2.imwrite('out/clean.png',clean); cv2.imwrite('out/mask.png',mask)
json.dump(cells,open('out/cells.json','w'))

# ---- step 2: tidy the screen's ceiling label, rebuild brushed metal under the knob values,
# ---- then cut the plate, the strip and the lit/unlit button textures
rng=np.random.default_rng(3)
clean=cv2.imread('out/clean.png')
m=np.zeros((H,W),np.uint8); m[130:170,1022:1176]=255
clean=cv2.inpaint(clean,m,9,cv2.INPAINT_TELEA)
c=clean.astype(np.float32)
def rowfill(x0,y0,x1,y1,edge=6):
    for y in range(y0,y1):
        left=c[y,x0-edge:x0].mean(axis=0); right=c[y,x1:x1+edge].mean(axis=0)
        t=np.linspace(0,1,x1-x0)[:,None]
        c[y,x0:x1]=left*(1-t)+right*t
    n=rng.normal(0,1,(y1-y0,x1-x0)).astype(np.float32)
    n=cv2.GaussianBlur(n,(0,0),sigmaX=9,sigmaY=0.4)*9
    lum=c[y0:y1,x0:x1].mean(axis=2,keepdims=True)/255
    c[y0:y1,x0:x1]+=n[...,None]*np.array([0.45,0.45,1.0])*lum*2
for cx,cy in big: rowfill(int(cx-62),674,int(cx+62),706)
for cx,cy in small: rowfill(int(cx-34),845,int(cx+34),869)
out=np.clip(c,0,255).astype(np.uint8); cv2.imwrite('out/clean2.png',out)
from PIL import Image
a=Image.open('out/clean2.png').convert('RGB')
a.crop((0,0,1448,997)).save('out/RCPlate.png')
a.crop((0,997,1448,1086)).save('out/RCStrip.png')
a.crop((876,921,982,967)).save('out/RCSegLit.png')
a.crop((244,921,362,969)).save('out/RCSegOff.png')
a.crop((958,28,1015,79)).save('out/RCABLit.png')
a.crop((1015,28,1072,79)).save('out/RCABOff.png')
