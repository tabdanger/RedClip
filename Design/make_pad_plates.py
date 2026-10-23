# Makes the full-screen iPad faces (RCPlate, RCPlatePlatinum) and the lit/unlit cell textures
# (RCSegLit/Off, RCABLit/Off, each with a Platinum twin) from Tyrone's pictures in this folder.
# Erases every part the app draws live (knob pointers and values, preset name, CLIP number,
# toggle and transport legends) so nothing shows twice. Run from Design/: python3 make_pad_plates.py
# (needs opencv-python); writes into out/. Positions are picture pixels, matching PlateLayout.pad.
import cv2, numpy as np, math, os
os.makedirs('out', exist_ok=True)
SRC = dict(red='RedClip-faceplate.png', plat='RedClip-faceplate-platinum.png')

def make(fin):
    img = cv2.imread(SRC[fin])
    P = fin == 'plat'
    # platinum offsets from red, per region (measured by matching)
    OFF = dict(top=(0,1), help=(-1,1), clip=(-1,-1), k_in=(1,-2), k_drive=(-1,-2), k_ceil=(-1,-2), k_mix=(-4,-2), k_out=(-4,-2),
               k_red=(0,0), k_fire=(0,0), v_in=(2,-2), v_drive=(1,-2), v_ceil=(0,-2), v_mix=(-3,-2), v_out=(-3,-1), v_red=(0,2), v_fire=(0,2),
               unity=(1,0), link=(-1,4), delta=(-1,0), bypass=(-3,4), tr=(0,6), t_exp=(-3,6), t_prog=(-3,6), t_file=(1,6))
    def off(k): return OFF.get(k,(0,0)) if P else (0,0)
    
    def erase(rect, mode, k=9, thr=25, dil=2, key=None, radius=3, extra=None):
        dx,dy = off(key)
        x,y,w,h = rect; x+=dx; y+=dy
        pad = k
        X0,Y0,X1,Y1 = x-pad, y-pad, x+w+pad, y+h+pad
        sub = img[Y0:Y1, X0:X1]
        g = cv2.cvtColor(sub, cv2.COLOR_BGR2GRAY)
        ker = cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(k,k))
        if mode == 'bright': d = cv2.morphologyEx(g, cv2.MORPH_TOPHAT, ker)
        elif mode == 'dark': d = cv2.morphologyEx(g, cv2.MORPH_BLACKHAT, ker)
        else:
            d = np.maximum(cv2.morphologyEx(g, cv2.MORPH_TOPHAT, ker), cv2.morphologyEx(g, cv2.MORPH_BLACKHAT, ker))
        if extra is not None: d = np.maximum(d, extra(sub))
        m = (d > thr).astype(np.uint8)
        lim = np.zeros_like(m); lim[pad:pad+h, pad:pad+w] = 1; m &= lim
        m = cv2.dilate(m, np.ones((2*dil+1,2*dil+1),np.uint8))
        img[Y0:Y1, X0:X1] = cv2.inpaint(sub, m*255, radius, cv2.INPAINT_TELEA)
    
    def rowfill(rect, key=None):
        # fill each row by interpolating between the pixels just outside the rect (keeps vertical gradients)
        dx,dy = off(key); x,y,w,h = rect; x+=dx; y+=dy
        a = img[y:y+h, x-3:x].astype(float).mean(1); b = img[y:y+h, x+w:x+w+3].astype(float).mean(1)
        t = np.linspace(0,1,w)[None,:,None]
        img[y:y+h, x:x+w] = (a[:,None,:]*(1-t) + b[:,None,:]*t).astype(np.uint8)
    
    def pointer(c, deg, r0, r1, wd, key):
        # The cap is brushed in rings and shaded by angle, so each pixel under the pointer is
        # rebuilt from the cap at the same radius just either side of it, blended by angle.
        dx,dy = off(key); cx,cy = c[0]+dx, c[1]+dy
        src = img.astype(float)
        def at(r, t):
            x, y = cx + r*math.sin(t), cy - r*math.cos(t)
            x0, y0 = int(x), int(y); fx, fy = x-x0, y-y0
            return (src[y0,x0]*(1-fx)*(1-fy) + src[y0,x0+1]*fx*(1-fy) + src[y0+1,x0]*(1-fx)*fy + src[y0+1,x0+1]*fx*fy)
        a = math.radians(deg); R = int(r1)+2
        for Y in range(int(cy)-R, int(cy)+R+1):
            for X in range(int(cx)-R, int(cx)+R+1):
                r = math.hypot(X-cx, Y-cy)
                if r < r0 or r > r1: continue
                th = math.atan2(X-cx, -(Y-cy)); d = (th - a + math.pi) % (2*math.pi) - math.pi
                hw = wd / r
                if abs(d) > hw: continue
                t = (d + hw) / (2*hw)
                img[Y,X] = np.clip(at(r, a-hw-0.5/r)*(1-t) + at(r, a+hw+0.5/r)*t, 0, 255)
    
    KNOBS = dict(red=[(180.5,588),(451,588),(722.5,588),(996,587.5),(1266.5,588),(172.5,802),(675.5,802.5)],
                 plat=[(181.5,586),(450,586),(721.5,586),(994,585.5),(1264,586),(172.5,802),(675.5,802.5)])
    # --- header
    rowfill((580,30,300,38), key='top')      # preset name
    rowfill((1219,31,38,42), key='help')         # "?"
    # --- clip number
    rowfill((703,412,72,42), key='clip')
    # --- knob pointers (center, angle in picture, from, to, width)
    KC = KNOBS['plat' if P else 'red']
    for c,d in zip(KC[:5], [49.5,-135,119.25,89.1,-19.1]): pointer(c, d, 30, 61, 7, None)
    pointer(KC[5],-8.1,11,31,5,None); pointer(KC[6],-40.5,11,31,5,None)
    # --- knob values
    for k,r in dict(v_in=(111,686,140,27), v_drive=(382,686,140,27), v_ceil=(652,686,140,27), v_mix=(926,686,140,27), v_out=(1197,686,140,27)).items():
        erase(r, 'dark' if P else 'bright', k=13, thr=22, key=k, radius=4)
    for k,r in dict(v_red=(140,853,66,20), v_fire=(642,853,66,20)).items():
        erase(r, 'dark' if P else 'bright', k=11, thr=22, key=k, radius=4)
    # --- toggle legends (button bodies stay)
    erase((300,820,142,24), 'any', k=15, thr=25, key='unity')
    erase((575,920,100,34), 'any', k=17, thr=25, key='link')
    erase((1213,808,125,26), 'any', k=17, thr=25, key='delta')
    erase((1200,920,145,34), 'any', k=21, thr=25, key='bypass')
    # --- transport live legends: PLAY, file name, progress dot, EXPORT
    erase((48,1025,90,26), 'any', k=17, thr=25, key='tr')
    erase((598,1025,190,26), 'any', k=17, thr=25, key='t_file')
    rowfill((788,1024,26,26), key='t_prog')
    erase((1295,1024,115,30), 'any', k=21, thr=25, key='t_exp')
    if P: erase((283,467,32,34), 'any', k=21, thr=20)   # stray cursor in the platinum art
    cv2.imwrite('out/' + ('RCPlatePlatinum' if P else 'RCPlate') + '.png', img)

def textures(fin):
    img = cv2.imread(SRC[fin]); P = fin == 'plat'
    def rowfill(x,y,w,h):
        a = img[y:y+h, x-3:x].astype(float).mean(1); b = img[y:y+h, x+w:x+w+3].astype(float).mean(1)
        t = np.linspace(0,1,w)[None,:,None]
        img[y:y+h, x:x+w] = (a[:,None,:]*(1-t) + b[:,None,:]*t).astype(np.uint8)
    def o(d): return d if P else (0,0)
    jobs = dict(SegLit=((886,927,108,43),(915,935,50,28),(-1,3)), SegOff=((218,926,128,44),(232,934,100,28),(1,3)),
                ABLit=((970,26,55,47),(984,34,28,32),(0,1)), ABOff=((1027,26,57,47),(1042,34,30,32),(0,1)))
    for name,((x,y,w,h),(tx,ty,tw,th),d) in jobs.items():
        dx,dy = o(d)
        rowfill(tx+dx,ty+dy,tw,th)
        cv2.imwrite(f'out/RC{name}{"Platinum" if P else ""}.png', img[y+dy:y+dy+h, x+dx:x+dx+w])

for fin in ('red', 'plat'):
    make(fin)
    textures(fin)
