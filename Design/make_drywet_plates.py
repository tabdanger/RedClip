# Dry/Wet + Broil faces (Oct 2026): Tyrone's four new pictures (*-drywet.png in this folder) differ from
# the approved faces only in the Wet/Dry/Output row and the Red/Fire/Broil row. Those bands are cut from
# the new pictures and laid into the current cleaned faces (the asset catalog), then everything the app
# draws live in them (knob pointers and values, the Unity legend) is erased so nothing shows twice.
# Run from Design/: python3 make_drywet_plates.py (needs opencv-python); writes into out/.
# Knob centres and every rectangle match PlateLayout.pad / .padPlatinum / .phone / .phonePlatinum.
import cv2, numpy as np, math, os
os.makedirs('out', exist_ok=True)
A = '../RedClip.swiftpm/Resources/Assets.xcassets/'

# name: (new picture, current face, platinum?, bands (x0, y0, x1, y1, dx, dy): new picture pixel = face pixel + (dx, dy))
FACES = dict(
    RCPlate=('RedClip-faceplate-drywet.png', 'RCPlate', False,
             [(832, 468, 1162, 722, 0, 0), (560, 733, 806, 874, 0, 0)]),
    RCPlatePlatinum=('RedClip-faceplate-platinum-drywet.png', 'RCPlatePlatinum', True,
             [(832, 468, 1162, 722, 0, 0), (538, 733, 1160, 874, 0, 0)]),
    RCPhonePlate=('RedClip-phone-drywet.png', 'RCPhonePlate', False,
             [(0, 938, 851, 1172, 0, 1), (0, 1182, 851, 1338, 0, 1)]),
    RCPhonePlatePlatinum=('RedClip-phone-platinum-drywet.png', 'RCPhonePlatePlatinum', True,
             [(0, 938, 850, 1172, 0, 2), (0, 1182, 850, 1338, 0, 2)]),
)

# knobs in the new bands: centre x, centre y, cap radius, pointer half-width (face pixels)
KNOBS = dict(
    RCPlate=[(940.3, 581.6, 42, 6), (1070.9, 583.5, 43, 6), (616.9, 804.3, 37, 5), (740.6, 805.4, 37, 5)],
    RCPlatePlatinum=[(909.3, 573.4, 42, 6), (1045.5, 572.1, 41, 6), (623.5, 805.2, 38, 5), (744.9, 803.5, 37, 5)],
    RCPhonePlate=[(201.3, 1033.4, 50, 6), (356.0, 1031.2, 48, 6), (548.5, 1047.3, 69, 7),
                  (185.0, 1259.9, 40, 5), (590.4, 1261.1, 42, 5), (737.3, 1262.8, 42, 5)],
    RCPhonePlatePlatinum=[(227.6, 1032.9, 49, 6), (419.6, 1032.4, 49, 6), (622.3, 1049.9, 65, 7),
                          (142.1, 1259.2, 42, 5), (590.8, 1263.4, 42, 5), (744.0, 1262.7, 42, 5)],
)

# printed values (and the Unity legend on the phones): x, y, w, h
TEXT = dict(
    RCPlate=[(910, 643, 62, 22), (1041, 643, 64, 22), (592, 854, 50, 21), (720, 854, 38, 21)],
    RCPlatePlatinum=[(882, 631, 60, 22), (1020, 631, 62, 22), (602, 856, 50, 21), (729, 856, 38, 21)],
    RCPhonePlate=[(166, 1093, 80, 26), (328, 1093, 56, 26), (504, 1135, 92, 27),
                  (158, 1309, 50, 24), (565, 1309, 52, 24), (716, 1309, 42, 24), (320, 1281, 156, 28)],
    RCPhonePlatePlatinum=[(202, 1098, 60, 26), (394, 1098, 56, 26), (578, 1136, 92, 27),
                          (124, 1309, 40, 24), (567, 1309, 52, 24), (727, 1309, 47, 24), (280, 1281, 149, 28)],
)

def patch(base, new, x0, y0, x1, y1, dx, dy, f=4):
    h, w = y1 - y0, x1 - x0
    src = new[y0 + dy:y1 + dy, x0 + dx:x1 + dx].astype(float)
    m = np.ones((h, w))
    for i in range(f):            # feathered edges
        a = (i + 1) / (f + 1)
        m[i, :] *= a; m[h - 1 - i, :] *= a; m[:, i] *= a; m[:, w - 1 - i] *= a
    m = m[..., None]
    base[y0:y1, x0:x1] = (src * m + base[y0:y1, x0:x1].astype(float) * (1 - m)).astype(np.uint8)

def pointer(img, cx, cy, R, wd, platinum):
    # Find the pointer: the narrow spoke that stands out (bright on red caps, dark on platinum)
    # from the cap's broad shading, between 45 and 80 % of the radius.
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(float)
    angs = np.arange(-150, 150.5, 0.5)
    prof = []
    for d in angs:
        t = math.radians(d)
        vals = [g[int(round(cy - r * math.cos(t))), int(round(cx + r * math.sin(t)))] for r in np.arange(0.45 * R, 0.8 * R, 1)]
        prof.append(np.mean(vals))
    prof = np.array(prof)
    base = np.array([np.median(prof[max(0, i - 40):i + 41]) for i in range(len(prof))])
    dev = (base - prof) if platinum else (prof - base)
    deg = angs[int(np.argmax(dev))]
    # Rebuild each pixel under it from the cap at the same radius just either side, blended by angle
    # (the cap is brushed in rings and shaded by angle).
    src = img.astype(float)
    def at(r, t):
        x, y = cx + r * math.sin(t), cy - r * math.cos(t)
        x0, y0 = int(x), int(y); fx, fy = x - x0, y - y0
        return (src[y0, x0] * (1 - fx) * (1 - fy) + src[y0, x0 + 1] * fx * (1 - fy)
                + src[y0 + 1, x0] * (1 - fx) * fy + src[y0 + 1, x0 + 1] * fx * fy)
    a = math.radians(deg); r0, r1 = 0.2 * R, 0.93 * R; Rr = int(r1) + 2
    for Y in range(int(cy) - Rr, int(cy) + Rr + 1):
        for X in range(int(cx) - Rr, int(cx) + Rr + 1):
            r = math.hypot(X - cx, Y - cy)
            if r < r0 or r > r1: continue
            th = math.atan2(X - cx, -(Y - cy)); d = (th - a + math.pi) % (2 * math.pi) - math.pi
            hw = wd / r
            if abs(d) > hw: continue
            t = (d + hw) / (2 * hw)
            img[Y, X] = np.clip(at(r, a - hw - 0.5 / r) * (1 - t) + at(r, a + hw + 0.5 / r) * t, 0, 255)
    return deg

def erase(img, rect, mode, k=13, thr=22, dil=2, radius=4):
    x, y, w, h = rect
    pad = k
    X0, Y0, X1, Y1 = x - pad, y - pad, x + w + pad, y + h + pad
    sub = img[Y0:Y1, X0:X1]
    g = cv2.cvtColor(sub, cv2.COLOR_BGR2GRAY)
    ker = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    d = cv2.morphologyEx(g, cv2.MORPH_TOPHAT if mode == 'bright' else cv2.MORPH_BLACKHAT, ker)
    m = (d > thr).astype(np.uint8)
    lim = np.zeros_like(m); lim[pad:pad + h, pad:pad + w] = 1; m &= lim
    m = cv2.dilate(m, np.ones((2 * dil + 1, 2 * dil + 1), np.uint8))
    img[Y0:Y1, X0:X1] = cv2.inpaint(sub, m * 255, radius, cv2.INPAINT_TELEA)

for name, (src, face, plat, bands) in FACES.items():
    img = cv2.imread(f'{A}{face}.imageset/{face}.png')
    new = cv2.imread(src)
    for b in bands: patch(img, new, *b)
    for (cx, cy, R, wd) in KNOBS[name]:
        deg = pointer(img, cx, cy, R, wd, plat)
        print(name, 'pointer at', deg)
    for r in TEXT[name]:
        erase(img, r, 'dark' if plat else 'bright', k=17 if r[3] >= 28 else 13)
    cv2.imwrite(f'out/{name}.png', img)
