# Run from the repo root: python3 Design/make_presets.py  (then re-add .delta: 1 to "Hear The Clip (Delta)")
# Original Red Clip factory presets. Fields:
# name, input, drive, ceiling, mix, output, clip(0 Hard 1 Classic 2 Modern), os(0 1x,1 2x,2 4x),
# red %, redMode(0 Modern 1 Classic), unity, fire %, box(0 Flat 1 Modern 2 Classic)
H,C,M=0,1,2
banks = {
"Essentials": [
 ("Default",                0,0,-0.3,100,0, M,1,  0,0,0,  0,0),
 ("Gentle Master",          2,0,-0.3,100,0, C,2, 25,0,0, 30,1),
 ("Loud Master",            3,4,-0.3,100,0, M,2, 55,1,0, 50,2),
 ("Drum Bus Smash",         0,9,-1.0, 70,0, H,2, 70,1,1, 20,0),
 ("808 Edge",               0,7,-0.3,100,0, M,2, 35,0,1, 65,0),
 ("Transient Shave",        3,0,-1.0,100,0, C,2,  0,0,1, 40,0),
],
"Mix Bus & Master": [
 ("Clean Peak Catch",       0,1,-0.3,100,0, C,2,  0,0,0, 15,0),
 ("Streaming Ready",        2,2,-1.0,100,0, C,2, 30,0,0, 35,1),
 ("Club Loud",              4,5,-0.3,100,0, M,2, 60,1,0, 55,2),
 ("Analog Glue Bus",        1,3,-0.5,100,0, C,2, 40,1,1, 30,2),
 ("Transparent +2",         2,0,-0.3,100,0, C,2, 20,0,0, 20,0),
 ("Dense Modern Master",    3,4,-0.3,100,0, M,2, 70,0,0, 45,1),
 ("Vintage Converter",      1,2,-0.3,100,0, C,2, 50,1,0, 60,2),
 ("Mix Bus Parallel",       0,8,-0.5, 40,0, M,2, 60,1,0, 30,0),
],
"Drums": [
 ("Kick Punch",             0,6,-1.0,100,1.0, H,2, 20,0,1, 10,0),
 ("Kick Sub Tame",          0,4,-0.5,100,0.5, C,2,  0,0,0, 25,0),
 ("Snare Crack",            0,8,-1.5,100,1.5, H,2, 30,1,1, 20,0),
 ("Snare Body",             0,5,-1.0,100,1.0, M,2, 55,1,0, 35,2),
 ("Clap Snap",              0,7,-1.0,100,1.0, H,2, 25,0,1, 30,0),
 ("Hats Tame",              0,3,-2.0,100,2.0, C,2,  0,0,0, 70,2),
 ("Perc Bite",              0,6,-1.0, 80,0.5, M,2, 40,0,0, 30,1),
 ("Drum Bus Glue",          0,4,-0.5,100,0, C,2, 45,1,1, 25,2),
 ("Room Crush",             0,12,-3.0,50,2.0, H,1, 80,1,0, 40,2),
 ("Breakbeat Grit",         0,9,-1.5, 85,1.0, H,1, 65,1,0, 15,2),
],
"808 & Bass": [
 ("808 Round",              0,5,-0.5,100,0, C,2, 30,0,0, 40,0),
 ("808 Growl",              0,10,-1.0,100,0.5, M,2, 60,1,0, 70,2),
 ("808 Click Keeper",       0,6,-0.5,100,0, H,2, 20,0,1, 20,0),
 ("Sub Control",            0,3,-1.0,100,1.0, C,2,  0,0,0, 30,0),
 ("Bass DI Warm",           0,4,-0.5,100,0, C,2, 45,1,1, 45,2),
 ("Synth Bass Edge",        0,7,-0.5,100,0, M,2, 40,0,0, 55,1),
 ("Reese Saturate",         0,9,-1.0, 80,0.5, M,2, 70,1,0, 60,2),
 ("Bass Parallel Fat",      0,11,-1.0,50,0, M,2, 75,1,0, 50,0),
],
"Vocals": [
 ("Lead Vocal Peaks",       0,2,-1.0,100,0.5, C,2,  0,0,1, 50,0),
 ("Rap Vocal Forward",      0,5,-1.0,100,0.5, M,2, 40,0,1, 55,1),
 ("Vocal Air Smooth",       0,3,-1.0,100,0.5, C,2, 20,0,1, 75,2),
 ("Backing Vocal Glue",     0,4,-1.5, 80,1.0, C,2, 35,1,1, 45,2),
 ("Ad-lib Grit",            0,9,-2.0, 70,1.5, H,2, 60,1,0, 30,0),
 ("Vocal Bus Density",      0,4,-0.5, 60,0, M,2, 50,1,1, 40,1),
 ("Telephone Crunch",       0,12,-4.0,100,3.5, H,0, 80,1,0, 0,2),
 ("Soft Sibilance Tame",    0,1,-1.5,100,1.0, C,2,  0,0,1, 90,2),
],
"Guitars": [
 ("Acoustic Strum Peaks",   0,2,-1.0,100,0.5, C,2, 15,0,1, 40,1),
 ("Electric Rhythm Push",   0,6,-1.0,100,0.5, M,2, 50,1,0, 35,2),
 ("Lead Guitar Sustain",    0,8,-1.0, 85,0.5, C,2, 60,1,0, 45,2),
 ("Clean Guitar Sparkle",   0,3,-0.5,100,0, C,2, 25,0,1, 20,1),
 ("Fuzz Wall",              0,12,-2.0,100,1.5, H,1, 90,1,0, 50,2),
],
"Keys & Synths": [
 ("Piano Peak Catch",       0,2,-0.5,100,0, C,2, 15,0,1, 25,1),
 ("Rhodes Warmth",          0,4,-0.5,100,0, C,2, 50,1,1, 45,2),
 ("Pad Density",            0,3,-1.0, 70,0.5, M,2, 55,1,0, 35,1),
 ("Pluck Snap",             0,6,-1.0,100,0.5, H,2, 30,0,1, 30,0),
 ("Supersaw Tame",          0,5,-1.0,100,0.5, M,2, 35,0,0, 70,2),
 ("Organ Drive",            0,8,-1.0,100,0.5, C,1, 70,1,0, 40,2),
],
"FX & Creative": [
 ("Lo-Fi Crush",            0,12,-6.0,100,5.0, H,0, 90,1,0, 0,2),
 ("Hear The Clip (Delta)",  0,6,-1.0,100,0, H,2,  0,0,0, 0,0),
 ("Distant Radio",          0,10,-8.0,100,7.0, H,0, 70,1,0, 80,2),
 ("Parallel Explode",       0,12,-2.0,30,0, H,1, 100,1,0, 20,0),
 ("Tape Shoulder",          0,6,-1.0,100,0.5, C,2, 80,1,1, 60,2),
],
"Trap Pack": [
 ("Trap Master",            3,4,-0.3,100,0, M,2, 60,1,0, 45,1),
 ("Trap 808 Slam",          0,10,-0.5,100,0, M,2, 55,1,0, 70,0),
 ("Trap Snare Crack",       0,9,-1.5,100,1.5, H,2, 35,1,1, 25,0),
 ("Trap Hats Bright",       0,4,-1.5,100,1.0, C,2,  0,0,0, 40,1),
 ("Trap Vocal Loud",        0,6,-1.0,100,0.5, M,2, 50,0,1, 55,1),
 ("Trap Drum Bus",          0,8,-1.0, 80,0.5, H,2, 60,1,0, 30,0),
],
"Boom Bap Pack": [
 ("Boom Bap Master",        2,3,-0.5,100,0, C,2, 55,1,0, 55,2),
 ("Dusty Drum Bus",         0,9,-1.5, 85,1.0, H,1, 70,1,0, 50,2),
 ("Boom Bap Kick Knock",    0,7,-1.0,100,1.0, H,2, 40,1,1, 20,2),
 ("SP Snare",               0,10,-2.0,100,1.5, H,0, 60,1,0, 30,2),
 ("Sample Chop Warmth",     0,5,-1.0,100,0.5, C,2, 60,1,1, 60,2),
],
"R&B / Neo Soul Pack": [
 ("Silk Master",            2,2,-0.5,100,0, C,2, 40,1,0, 50,2),
 ("Neo Soul Drums",         0,5,-1.0, 80,0.5, C,2, 50,1,1, 45,2),
 ("R&B Lead Vocal",         0,3,-1.0,100,0.5, C,2, 25,0,1, 65,2),
 ("Warm Keys Bus",          0,4,-0.5,100,0, C,2, 55,1,1, 50,2),
 ("Round Bass",             0,5,-0.5,100,0, C,2, 45,1,0, 45,2),
],
"Pop Pack": [
 ("Pop Master Bright",      3,3,-0.3,100,0, M,2, 45,0,0, 35,1),
 ("Pop Drum Bus",           0,6,-0.5,100,0, M,2, 50,0,1, 30,1),
 ("Pop Vocal Up Front",     0,4,-1.0,100,0.5, M,2, 35,0,1, 55,1),
 ("Pop Synth Bus",          0,4,-0.5,100,0, M,2, 40,0,0, 45,1),
 ("Pop Kick Click",         0,7,-1.0,100,1.0, H,2, 25,0,1, 15,0),
],
"EDM Pack": [
 ("Festival Master",        4,6,-0.3,100,0, M,2, 75,1,0, 50,1),
 ("Big Room Kick",          0,10,-0.5,100,0, H,2, 50,1,0, 25,0),
 ("Drop Bus Slam",          0,9,-0.5, 90,0, M,2, 70,1,0, 45,1),
 ("Lead Synth Bite",        0,6,-1.0,100,0.5, M,2, 45,0,0, 60,1),
 ("Riser Glue",             0,5,-1.0, 70,0.5, C,2, 50,1,0, 50,2),
],
"Rock Pack": [
 ("Rock Master",            3,4,-0.3,100,0, C,2, 60,1,0, 45,2),
 ("Rock Drum Bus Crush",    0,9,-1.0, 70,0.5, H,2, 70,1,0, 35,2),
 ("Rock Snare Fat",         0,7,-1.0,100,1.0, C,2, 55,1,1, 30,2),
 ("Guitar Bus Wall",        0,7,-1.0,100,0.5, M,2, 60,1,0, 45,2),
 ("Rock Vocal Grit",        0,6,-1.0, 85,0.5, M,2, 55,1,1, 50,2),
],
"Lo-Fi Pack": [
 ("Lo-Fi Master",           1,4,-1.0,100,0.5, C,1, 70,1,0, 75,2),
 ("Lo-Fi Drums Dusty",      0,10,-3.0,100,2.5, H,0, 75,1,0, 60,2),
 ("Lo-Fi Keys Tape",        0,5,-1.5,100,1.0, C,1, 70,1,1, 70,2),
 ("Lo-Fi Bass Soft",        0,4,-1.0,100,0.5, C,2, 50,1,0, 60,2),
],
"Drill Pack": [
 ("Drill Master",           3,5,-0.3,100,0, M,2, 65,1,0, 45,1),
 ("Drill 808 Slide",        0,11,-0.5,100,0, M,2, 60,1,0, 75,0),
 ("Drill Snare Snap",       0,9,-1.5,100,1.5, H,2, 40,1,1, 25,0),
 ("Drill Vocal Aggro",      0,8,-1.0,100,0.5, M,2, 55,1,1, 50,1),
],
"Afrobeats Pack": [
 ("Afro Master Warm",       2,3,-0.3,100,0, C,2, 50,1,0, 45,2),
 ("Afro Perc Bus",          0,5,-1.0, 85,0.5, M,2, 40,0,1, 35,1),
 ("Afro Log Drum",          0,7,-0.5,100,0, M,2, 45,1,0, 50,0),
 ("Afro Vocal Smooth",      0,3,-1.0,100,0.5, C,2, 30,0,1, 65,2),
],
"Gospel Pack": [
 ("Gospel Master",          2,3,-0.3,100,0, C,2, 45,1,0, 45,2),
 ("Choir Bus Glue",         0,4,-1.0, 80,0.5, C,2, 45,1,1, 55,2),
 ("Gospel Drums Live",      0,6,-1.0, 80,0.5, M,2, 55,1,0, 35,2),
 ("Organ & Keys Bus",       0,5,-0.5,100,0, C,2, 55,1,1, 50,2),
],
}
fields=[("inputDB",1),("driveDB",2),("ceilingDB",3),("mix",4),("outputDB",5),("clipMode",6),("oversampling",7),
        ("gold",8),("goldMode",9),("unity",10),("alchemy",11),("boxTone",12)]
defaults={"inputDB":0,"driveDB":0,"ceilingDB":-0.3,"mix":100,"outputDB":0,"clipMode":2,"oversampling":1,
          "gold":0,"goldMode":0,"unity":0,"alchemy":0,"boxTone":0}
names=set(); n=0
out=["// Original Red Clip factory presets: instrument banks and producer-style packs.",
     "// Made for Red Clip's own controls (no other product's presets were copied).",
     "// Keep the order stable: hosts may remember a factory preset by its number.",
     "",
     "extension Preset {","    static let factory: [Preset] = ["]
for bank,rows in banks.items():
    out.append(f"        // {bank}")
    for r in rows:
        name=r[0]; assert name not in names, name; names.add(name); n+=1
        # sanity: output must not push the ceiling past 0 dBFS
        assert r[3]+r[5] <= 0.01, name
        vals=[]
        for f,i in fields:
            v=r[i]
            if v!=defaults[f]: vals.append(f".{f}: {v}")
        vs="[:]" if not vals else "["+", ".join(vals)+"]"
        out.append(f'        Preset(bank: "{bank}", name: "{name}", values: {vs}),')
out[-1]=out[-1].rstrip(",")
out+=["    ]","}",""]
open('RedClip.swiftpm/FactoryPresets.swift','w').write("\n".join(out))
print(n,"presets in",len(banks),"banks")
