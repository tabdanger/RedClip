import SwiftUI
import UIKit

/// Where everything sits on a faceplate picture. The iPad and iPhone faces share every control
/// and behaviour; only these positions differ. All values are pixels in the picture.
struct PlateLayout {
    struct Knob {
        let param: Param
        let center: CGPoint
        let pointerFrom: CGFloat
        let pointerTo: CGFloat
        let pointerWidth: CGFloat
        let value: CGRect
        let valueFont: CGFloat
        let topic: HelpTopic
    }
    struct Segments {
        let param: Param
        let cells: [(String, CGFloat, CGFloat)]   // label, left x, right x
        let y: CGFloat
        let h: CGFloat
        let font: CGFloat
        let topic: HelpTopic
    }
    struct Toggle {
        let rect: CGRect
        let font: CGFloat
    }
    struct Meter {
        let frame: CGRect                         // the view's rectangle
        let strips: [(CGFloat, CGFloat)]          // two strips: left x, right x
        let slots: [(CGFloat, CGFloat)]           // LED rows: top y, bottom y (bottom row last)
        let markY: [CGFloat]                      // rows of the 0, -6, -12, -18, -24, -36, -60 marks
        let backTop: CGFloat
        let backHeight: CGFloat
    }
    struct Transport {
        let play, load, samples, demo, fileName, progress, export: CGRect
        let font: CGFloat
    }

    let plate: String                 // asset base name (finish suffix is added)
    let segLit: String, segOff: String, abLit: String, abOff: String
    let size: CGSize                  // the plate picture
    let canvas: CGSize                // plate + (iPad) the separate transport strip
    let strip: String?                // iPad: transport strip picture under the plate
    let pluginHeight: CGFloat         // rows shown inside a DAW (no transport)

    let presetPrev, presetNext, presetName: CGRect
    let presetFont: CGFloat
    let a, b, undo, help, power: CGRect
    let letterFont: CGFloat
    let helpFont: CGFloat
    let powerIcon: CGFloat

    let meterIn, meterOut: Meter
    let screen: CGRect
    let scopeTextScale: CGFloat
    let clip: CGRect
    let clipNumber: CGPoint           // centre of the number, in picture pixels
    let clipFont: CGFloat

    var knobs: [Knob]
    var segments: [Segments]
    var unity: Toggle
    let link, delta: Toggle
    let bypass: Toggle
    let transport: Transport
    let bubbleScale: CGFloat          // help bubbles sized for this face

    /// Red and platinum pictures were drawn separately, so each has its own measured positions
    /// (on the iPhone the Wet / Dry / Output and Red / Fire / Broil rows are laid out differently).
    static func current(_ faceplate: Faceplate) -> PlateLayout {
        let platinum = faceplate == .face1Platinum
        if UIDevice.current.userInterfaceIdiom == .phone { return platinum ? .phonePlatinum : .phone }
        return platinum ? .padPlatinum : .pad
    }

    // MARK: iPad (1448 x 1086, full screen, transport built into the picture)
    // Measured from Tyrone's full-screen iPad art (Design/RedClip-faceplate*.png).
    // The Wet / Dry and Fire / Broil areas come from the Dry/Wet + Broil art (Design/make_drywet_plates.py).

    static let pad = PlateLayout(
        plate: "RCPlate", segLit: "RCSegLit", segOff: "RCSegOff", abLit: "RCABLit", abOff: "RCABOff",
        size: CGSize(width: 1448, height: 1086), canvas: CGSize(width: 1448, height: 1086),
        strip: nil, pluginHeight: 998,
        presetPrev: CGRect(x: 515, y: 22, width: 55, height: 53),
        presetNext: CGRect(x: 878, y: 22, width: 55, height: 53),
        presetName: CGRect(x: 570, y: 22, width: 308, height: 53), presetFont: 22,
        a: CGRect(x: 970, y: 26, width: 55, height: 47), b: CGRect(x: 1027, y: 26, width: 57, height: 47),
        undo: CGRect(x: 1133, y: 23, width: 60, height: 53), help: CGRect(x: 1207, y: 23, width: 61, height: 54),
        power: CGRect(x: 1305, y: 13, width: 72, height: 72),
        letterFont: 23, helpFont: 31, powerIcon: 31,
        meterIn: Meter(frame: CGRect(x: 80, y: 147, width: 76, height: 252),
                       strips: [(85, 105), (127, 148)], slots: padSlots,
                       markY: [157, 200, 242, 283, 325, 367, 394], backTop: 150, backHeight: 248),
        meterOut: Meter(frame: CGRect(x: 1252, y: 147, width: 74, height: 252),
                        strips: [(1258, 1279), (1303, 1322)], slots: padSlots,
                        markY: [157, 200, 242, 283, 325, 367, 394], backTop: 150, backHeight: 248),
        screen: CGRect(x: 249, y: 125, width: 957, height: 265), scopeTextScale: 1,
        clip: CGRect(x: 586, y: 408, width: 278, height: 51), clipNumber: CGPoint(x: 739, y: 432.5), clipFont: 40,
        knobs: [
            Knob(param: .inputDB, center: CGPoint(x: 180.5, y: 588), pointerFrom: 36, pointerTo: 58, pointerWidth: 6,
                 value: CGRect(x: 110.5, y: 684, width: 140, height: 30), valueFont: 22, topic: .input),
            Knob(param: .driveDB, center: CGPoint(x: 451, y: 588), pointerFrom: 36, pointerTo: 58, pointerWidth: 6,
                 value: CGRect(x: 381, y: 684, width: 140, height: 30), valueFont: 22, topic: .drive),
            Knob(param: .ceilingDB, center: CGPoint(x: 722.5, y: 588), pointerFrom: 36, pointerTo: 58, pointerWidth: 6,
                 value: CGRect(x: 652.5, y: 684, width: 140, height: 30), valueFont: 22, topic: .ceiling),
            Knob(param: .wet, center: CGPoint(x: 940.3, y: 581.6), pointerFrom: 21, pointerTo: 35, pointerWidth: 5,
                 value: CGRect(x: 880.3, y: 640, width: 120, height: 26), valueFont: 20, topic: .wet),
            Knob(param: .dry, center: CGPoint(x: 1070.9, y: 583.5), pointerFrom: 21, pointerTo: 35, pointerWidth: 5,
                 value: CGRect(x: 1010.9, y: 640, width: 120, height: 26), valueFont: 20, topic: .dry),
            Knob(param: .outputDB, center: CGPoint(x: 1266.5, y: 588), pointerFrom: 36, pointerTo: 58, pointerWidth: 6,
                 value: CGRect(x: 1196.5, y: 684, width: 140, height: 30), valueFont: 22, topic: .output),
            Knob(param: .gold, center: CGPoint(x: 172.5, y: 802), pointerFrom: 17, pointerTo: 30, pointerWidth: 4.5,
                 value: CGRect(x: 134.5, y: 851, width: 76, height: 24), valueFont: 16, topic: .red),
            Knob(param: .alchemy, center: CGPoint(x: 616.9, y: 804.3), pointerFrom: 17, pointerTo: 30, pointerWidth: 4.5,
                 value: CGRect(x: 578.9, y: 852, width: 76, height: 24), valueFont: 16, topic: .fire),
            Knob(param: .broil, center: CGPoint(x: 740.6, y: 805.4), pointerFrom: 17, pointerTo: 30, pointerWidth: 4.5,
                 value: CGRect(x: 700.6, y: 852, width: 76, height: 24), valueFont: 16, topic: .broil)
        ],
        segments: [
            Segments(param: .goldMode, cells: [("MODERN", 258, 369), ("CLASSIC", 369, 482)], y: 762, h: 36, font: 15, topic: .redStyle),
            Segments(param: .mixUnlink, cells: [("LINKED", 881, 1000), ("UNLINKED", 1000, 1134)], y: 677, h: 34, font: 15, topic: .mixLink),
            Segments(param: .boxTone, cells: [("FLAT", 826, 923), ("MODERN", 923, 1029), ("CLASSIC", 1029, 1138)], y: 799, h: 39, font: 15, topic: .boxTone),
            Segments(param: .clipMode, cells: [("HARD", 93, 217), ("CLASSIC", 217, 347), ("MODERN", 347, 475)], y: 926, h: 44, font: 17, topic: .clipMode),
            Segments(param: .oversampling, cells: [("1X", 768, 885), ("2X", 885, 995), ("4X", 995, 1116)], y: 927, h: 43, font: 17, topic: .oversampling)
        ],
        unity: Toggle(rect: CGRect(x: 289, y: 812, width: 163, height: 39), font: 16),
        link: Toggle(rect: CGRect(x: 558, y: 910, width: 132, height: 52), font: 18),
        delta: Toggle(rect: CGRect(x: 1203, y: 799, width: 143, height: 41), font: 17),
        bypass: Toggle(rect: CGRect(x: 1184, y: 910, width: 174, height: 53), font: 18),
        transport: Transport(play: CGRect(x: 31, y: 1013, width: 121, height: 47),
                             load: CGRect(x: 166, y: 1013, width: 123, height: 47),
                             samples: CGRect(x: 302, y: 1013, width: 152, height: 47),
                             demo: CGRect(x: 468, y: 1013, width: 114, height: 47),
                             fileName: CGRect(x: 601, y: 1025, width: 180, height: 26),
                             progress: CGRect(x: 795, y: 1022, width: 457, height: 30),
                             export: CGRect(x: 1280, y: 1014, width: 137, height: 46), font: 18),
        bubbleScale: 1)

    static let padSlots: [(CGFloat, CGFloat)] = [(153, 159), (165, 169), (174, 178), (182, 188), (192, 197), (202, 208),
        (210, 216), (220, 227), (230, 237), (241, 246), (251, 257), (261, 268),
        (271, 278), (283, 288), (293, 299), (303, 309), (314, 320), (324, 330),
        (335, 341), (345, 351), (356, 362), (366, 372), (376, 383), (387, 394)]

    static let padPlatinumSlots: [(CGFloat, CGFloat)] = [(152, 158), (163, 168), (172, 178), (181, 187), (191, 196), (200, 206),
        (209, 215), (219, 225), (228, 235), (239, 245), (249, 255), (259, 265),
        (269, 276), (280, 287), (291, 297), (301, 307), (312, 318), (322, 328),
        (332, 339), (343, 349), (354, 360), (363, 370), (374, 381), (385, 392)]

    static let padPlatinum = PlateLayout(
        plate: "RCPlate", segLit: "RCSegLit", segOff: "RCSegOff", abLit: "RCABLit", abOff: "RCABOff",
        size: CGSize(width: 1448, height: 1086), canvas: CGSize(width: 1448, height: 1086),
        strip: nil, pluginHeight: 1005,
        presetPrev: CGRect(x: 515, y: 23, width: 55, height: 53),
        presetNext: CGRect(x: 878, y: 23, width: 55, height: 53),
        presetName: CGRect(x: 570, y: 23, width: 308, height: 53), presetFont: 22,
        a: CGRect(x: 970, y: 27, width: 55, height: 47), b: CGRect(x: 1027, y: 27, width: 57, height: 47),
        undo: CGRect(x: 1133, y: 24, width: 60, height: 53), help: CGRect(x: 1206, y: 24, width: 61, height: 54),
        power: CGRect(x: 1301, y: 15, width: 72, height: 72),
        letterFont: 23, helpFont: 31, powerIcon: 31,
        meterIn: Meter(frame: CGRect(x: 80, y: 145, width: 76, height: 252),
                       strips: [(86, 106), (129, 149)], slots: padPlatinumSlots,
                       markY: [155, 198, 240, 281, 323, 365, 392], backTop: 149, backHeight: 247),
        meterOut: Meter(frame: CGRect(x: 1248, y: 145, width: 74, height: 252),
                        strips: [(1254, 1274), (1298, 1318)], slots: padPlatinumSlots,
                        markY: [155, 198, 240, 281, 323, 365, 392], backTop: 149, backHeight: 247),
        screen: CGRect(x: 248, y: 122, width: 957, height: 265), scopeTextScale: 1,
        clip: CGRect(x: 585, y: 407, width: 278, height: 51), clipNumber: CGPoint(x: 738, y: 431.5), clipFont: 40,
        knobs: [
            Knob(param: .inputDB, center: CGPoint(x: 181.5, y: 586), pointerFrom: 36, pointerTo: 58, pointerWidth: 6,
                 value: CGRect(x: 113.5, y: 682, width: 140, height: 30), valueFont: 22, topic: .input),
            Knob(param: .driveDB, center: CGPoint(x: 450, y: 586), pointerFrom: 36, pointerTo: 58, pointerWidth: 6,
                 value: CGRect(x: 381, y: 682, width: 140, height: 30), valueFont: 22, topic: .drive),
            Knob(param: .ceilingDB, center: CGPoint(x: 721.5, y: 586), pointerFrom: 36, pointerTo: 58, pointerWidth: 6,
                 value: CGRect(x: 651.5, y: 682, width: 140, height: 30), valueFont: 22, topic: .ceiling),
            Knob(param: .wet, center: CGPoint(x: 909.3, y: 573.4), pointerFrom: 21, pointerTo: 35, pointerWidth: 5,
                 value: CGRect(x: 850.3, y: 628, width: 120, height: 26), valueFont: 20, topic: .wet),
            Knob(param: .dry, center: CGPoint(x: 1045.5, y: 572.1), pointerFrom: 21, pointerTo: 35, pointerWidth: 5,
                 value: CGRect(x: 987.5, y: 628, width: 120, height: 26), valueFont: 20, topic: .dry),
            Knob(param: .outputDB, center: CGPoint(x: 1264, y: 586), pointerFrom: 36, pointerTo: 58, pointerWidth: 6,
                 value: CGRect(x: 1191, y: 683, width: 140, height: 30), valueFont: 22, topic: .output),
            Knob(param: .gold, center: CGPoint(x: 172.5, y: 802), pointerFrom: 17, pointerTo: 30, pointerWidth: 4.5,
                 value: CGRect(x: 134.5, y: 853, width: 76, height: 24), valueFont: 16, topic: .red),
            Knob(param: .alchemy, center: CGPoint(x: 623.5, y: 805.2), pointerFrom: 17, pointerTo: 30, pointerWidth: 4.5,
                 value: CGRect(x: 586.5, y: 854, width: 76, height: 24), valueFont: 16, topic: .fire),
            Knob(param: .broil, center: CGPoint(x: 744.9, y: 803.5), pointerFrom: 17, pointerTo: 30, pointerWidth: 4.5,
                 value: CGRect(x: 707.9, y: 854, width: 76, height: 24), valueFont: 16, topic: .broil)
        ],
        segments: [
            Segments(param: .goldMode, cells: [("MODERN", 259, 370), ("CLASSIC", 370, 483)], y: 762, h: 36, font: 15, topic: .redStyle),
            Segments(param: .mixUnlink, cells: [("LINKED", 857, 978), ("UNLINKED", 978, 1114)], y: 660, h: 40, font: 16, topic: .mixLink),
            Segments(param: .boxTone, cells: [("FLAT", 838, 927), ("MODERN", 927, 1028), ("CLASSIC", 1028, 1137)], y: 800, h: 42, font: 15, topic: .boxTone),
            Segments(param: .clipMode, cells: [("HARD", 94, 218), ("CLASSIC", 218, 348), ("MODERN", 348, 476)], y: 929, h: 44, font: 17, topic: .clipMode),
            Segments(param: .oversampling, cells: [("1X", 767, 884), ("2X", 884, 994), ("4X", 994, 1115)], y: 930, h: 43, font: 17, topic: .oversampling)
        ],
        unity: Toggle(rect: CGRect(x: 290, y: 812, width: 163, height: 39), font: 16),
        link: Toggle(rect: CGRect(x: 557, y: 914, width: 132, height: 52), font: 18),
        delta: Toggle(rect: CGRect(x: 1202, y: 799, width: 143, height: 41), font: 17),
        bypass: Toggle(rect: CGRect(x: 1181, y: 914, width: 174, height: 53), font: 18),
        transport: Transport(play: CGRect(x: 31, y: 1019, width: 121, height: 47),
                             load: CGRect(x: 165, y: 1019, width: 123, height: 47),
                             samples: CGRect(x: 304, y: 1019, width: 152, height: 47),
                             demo: CGRect(x: 471, y: 1019, width: 114, height: 47),
                             fileName: CGRect(x: 602, y: 1031, width: 180, height: 26),
                             progress: CGRect(x: 792, y: 1028, width: 457, height: 30),
                             export: CGRect(x: 1277, y: 1020, width: 137, height: 46), font: 18),
        bubbleScale: 1)


    // MARK: iPhone (851 x 1848, portrait, transport built into the picture)
    // Measured from the approved iPhone Face1 art; the Dry/Wet + Broil rows from Design/make_drywet_plates.py.

    static let phoneSlots: [(CGFloat, CGFloat)] = [(364, 369), (374, 380), (385, 390), (394, 399), (404, 409), (413, 418),
        (423, 428), (432, 439), (443, 449), (454, 459), (465, 470), (475, 481), (486, 491), (497, 502),
        (508, 514), (519, 525), (530, 535), (540, 546), (551, 557), (563, 569), (573, 579), (584, 590),
        (595, 601), (606, 613)]

    static let phone = PlateLayout(
        plate: "RCPhonePlate", segLit: "RCPhoneSegLit", segOff: "RCPhoneSegOff", abLit: "RCPhoneABLit", abOff: "RCPhoneABOff",
        size: CGSize(width: 851, height: 1848), canvas: CGSize(width: 851, height: 1848),
        strip: nil, pluginHeight: 1641,
        presetPrev: CGRect(x: 90, y: 244, width: 50, height: 52),
        presetNext: CGRect(x: 712, y: 244, width: 50, height: 52),
        presetName: CGRect(x: 140, y: 244, width: 572, height: 52), presetFont: 22,
        a: CGRect(x: 400, y: 161, width: 56, height: 51), b: CGRect(x: 456, y: 161, width: 56, height: 51),
        undo: CGRect(x: 542, y: 160, width: 58, height: 53), help: CGRect(x: 612, y: 158, width: 61, height: 57),
        power: CGRect(x: 689, y: 152, width: 69, height: 69),
        letterFont: 25, helpFont: 31, powerIcon: 30,
        meterIn: Meter(frame: CGRect(x: 66, y: 352, width: 80, height: 272),
                       strips: [(73, 96), (112, 134)], slots: phoneSlots,
                       markY: [364, 410, 454, 498, 541, 584, 629], backTop: 358, backHeight: 260),
        meterOut: Meter(frame: CGRect(x: 673, y: 352, width: 80, height: 272),
                        strips: [(680, 703), (720, 742)], slots: phoneSlots,
                        markY: [364, 410, 454, 498, 541, 584, 629], backTop: 358, backHeight: 260),
        screen: CGRect(x: 196, y: 321.6, width: 459.7, height: 281), scopeTextScale: 1,
        clip: CGRect(x: 304, y: 620, width: 243, height: 52), clipNumber: CGPoint(x: 430, y: 647.5), clipFont: 40,
        knobs: [
            Knob(param: .inputDB, center: CGPoint(x: 182.5, y: 810.5), pointerFrom: 36, pointerTo: 56, pointerWidth: 6,
                 value: CGRect(x: 103.5, y: 900, width: 160, height: 32), valueFont: 22, topic: .input),
            Knob(param: .driveDB, center: CGPoint(x: 424.7, y: 811), pointerFrom: 36, pointerTo: 56, pointerWidth: 6,
                 value: CGRect(x: 344.5, y: 900, width: 160, height: 32), valueFont: 22, topic: .drive),
            Knob(param: .ceilingDB, center: CGPoint(x: 670.7, y: 811.7), pointerFrom: 36, pointerTo: 56, pointerWidth: 6,
                 value: CGRect(x: 591, y: 900, width: 160, height: 32), valueFont: 22, topic: .ceiling),
            Knob(param: .wet, center: CGPoint(x: 201.3, y: 1033.4), pointerFrom: 24, pointerTo: 41, pointerWidth: 5,
                 value: CGRect(x: 141.3, y: 1091, width: 120, height: 28), valueFont: 21, topic: .wet),
            Knob(param: .dry, center: CGPoint(x: 356, y: 1031.2), pointerFrom: 24, pointerTo: 41, pointerWidth: 5,
                 value: CGRect(x: 296, y: 1091, width: 120, height: 28), valueFont: 21, topic: .dry),
            Knob(param: .outputDB, center: CGPoint(x: 548.5, y: 1047.3), pointerFrom: 36, pointerTo: 56, pointerWidth: 6,
                 value: CGRect(x: 468.5, y: 1132, width: 160, height: 32), valueFont: 22, topic: .output),
            Knob(param: .gold, center: CGPoint(x: 185, y: 1259.9), pointerFrom: 16, pointerTo: 28, pointerWidth: 4,
                 value: CGRect(x: 145, y: 1306, width: 80, height: 27), valueFont: 17, topic: .red),
            Knob(param: .alchemy, center: CGPoint(x: 590.4, y: 1261.1), pointerFrom: 16, pointerTo: 28, pointerWidth: 4,
                 value: CGRect(x: 550.4, y: 1306, width: 80, height: 27), valueFont: 17, topic: .fire),
            Knob(param: .broil, center: CGPoint(x: 737.3, y: 1262.8), pointerFrom: 16, pointerTo: 28, pointerWidth: 4,
                 value: CGRect(x: 697.3, y: 1306, width: 80, height: 27), valueFont: 17, topic: .broil)
        ],
        segments: [
            Segments(param: .goldMode, cells: [("MODERN", 277, 392), ("CLASSIC", 392, 508)], y: 1214, h: 40, font: 16, topic: .redStyle),
            Segments(param: .mixUnlink, cells: [("LINKED", 133, 276), ("UNLINKED", 284, 422)], y: 1123, h: 41, font: 16, topic: .mixLink),
            Segments(param: .boxTone, cells: [("FLAT", 104, 228), ("MODERN", 228, 350), ("CLASSIC", 350, 472)], y: 1386, h: 47, font: 17, topic: .boxTone),
            Segments(param: .clipMode, cells: [("HARD", 143, 330), ("CLASSIC", 330, 519), ("MODERN", 519, 709)], y: 1488, h: 44, font: 17, topic: .clipMode),
            Segments(param: .oversampling, cells: [("1X", 272, 376), ("2X", 376, 475), ("4X", 475, 578)], y: 1579, h: 43, font: 17, topic: .oversampling)
        ],
        unity: Toggle(rect: CGRect(x: 309, y: 1275, width: 177, height: 48), font: 17),
        link: Toggle(rect: CGRect(x: 72, y: 1566, width: 154, height: 54), font: 20),
        delta: Toggle(rect: CGRect(x: 575, y: 1387, width: 170, height: 49), font: 18),
        bypass: Toggle(rect: CGRect(x: 631, y: 1566, width: 147, height: 55), font: 17),
        transport: Transport(play: CGRect(x: 86, y: 1650, width: 157, height: 51),
                             load: CGRect(x: 250, y: 1650, width: 155, height: 51),
                             samples: CGRect(x: 419, y: 1650, width: 174, height: 51),
                             demo: CGRect(x: 608, y: 1650, width: 162, height: 51),
                             fileName: CGRect(x: 105, y: 1721, width: 150, height: 28),
                             progress: CGRect(x: 276, y: 1720, width: 282, height: 30),
                             export: CGRect(x: 601, y: 1711, width: 151, height: 53), font: 18),
        bubbleScale: 1.9)

    /// The platinum iPhone face: everything sits where the red one has it except the Wet / Dry /
    /// Output and Red / Fire / Broil rows.
    static let phonePlatinum: PlateLayout = {
        var l = PlateLayout.phone
        l.knobs = l.knobs.filter { [Param.inputDB, .driveDB, .ceilingDB].contains($0.param) } + [
            Knob(param: .wet, center: CGPoint(x: 227.6, y: 1032.9), pointerFrom: 24, pointerTo: 41, pointerWidth: 5,
                 value: CGRect(x: 167.6, y: 1096, width: 120, height: 28), valueFont: 21, topic: .wet),
            Knob(param: .dry, center: CGPoint(x: 419.6, y: 1032.4), pointerFrom: 24, pointerTo: 41, pointerWidth: 5,
                 value: CGRect(x: 359.6, y: 1096, width: 120, height: 28), valueFont: 21, topic: .dry),
            Knob(param: .outputDB, center: CGPoint(x: 622.3, y: 1049.9), pointerFrom: 34, pointerTo: 53, pointerWidth: 6,
                 value: CGRect(x: 542.3, y: 1133, width: 160, height: 32), valueFont: 22, topic: .output),
            Knob(param: .gold, center: CGPoint(x: 142.1, y: 1259.2), pointerFrom: 16, pointerTo: 28, pointerWidth: 4,
                 value: CGRect(x: 102.1, y: 1306, width: 80, height: 27), valueFont: 17, topic: .red),
            Knob(param: .alchemy, center: CGPoint(x: 590.8, y: 1263.4), pointerFrom: 16, pointerTo: 28, pointerWidth: 4,
                 value: CGRect(x: 550.8, y: 1306, width: 80, height: 27), valueFont: 17, topic: .fire),
            Knob(param: .broil, center: CGPoint(x: 744, y: 1262.7), pointerFrom: 16, pointerTo: 28, pointerWidth: 4,
                 value: CGRect(x: 704, y: 1306, width: 80, height: 27), valueFont: 17, topic: .broil)
        ]
        l.segments = l.segments.map { s in
            switch s.param {
            case .goldMode:
                return Segments(param: .goldMode, cells: [("MODERN", 237, 354), ("CLASSIC", 354, 470)], y: 1214, h: 41, font: 16, topic: .redStyle)
            case .mixUnlink:
                return Segments(param: .mixUnlink, cells: [("LINKED", 163, 319), ("UNLINKED", 342, 500)], y: 1129, h: 40, font: 16, topic: .mixLink)
            default:
                return s
            }
        }
        l.unity = Toggle(rect: CGRect(x: 269, y: 1274, width: 170, height: 44), font: 17)
        return l
    }()
}
