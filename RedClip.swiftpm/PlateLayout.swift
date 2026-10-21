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

    let knobs: [Knob]
    let segments: [Segments]
    let unity, link, delta: Toggle
    let bypass: Toggle
    let transport: Transport
    let bubbleScale: CGFloat          // help bubbles sized for this face

    static var current: PlateLayout {
        UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
    }

    // MARK: iPad (1448 x 997 plate + 89 px transport strip)

    static let pad = PlateLayout(
        plate: "RCPlate", segLit: "RCSegLit", segOff: "RCSegOff", abLit: "RCABLit", abOff: "RCABOff",
        size: CGSize(width: 1448, height: 997), canvas: CGSize(width: 1448, height: 1086),
        strip: "RCStrip", pluginHeight: 997,
        presetPrev: CGRect(x: 523, y: 25, width: 52, height: 53),
        presetNext: CGRect(x: 871, y: 25, width: 52, height: 53),
        presetName: CGRect(x: 578, y: 25, width: 290, height: 53), presetFont: 21,
        a: CGRect(x: 958, y: 28, width: 57, height: 51), b: CGRect(x: 1015, y: 28, width: 57, height: 51),
        undo: CGRect(x: 1112, y: 26, width: 62, height: 53), help: CGRect(x: 1182, y: 27, width: 62, height: 54),
        power: CGRect(x: 1275, y: 17, width: 70, height: 70),
        letterFont: 22, helpFont: 30, powerIcon: 30,
        meterIn: Meter(frame: CGRect(x: 111, y: 148, width: 72, height: 251),
                       strips: [(115, 135), (157, 176)], slots: padSlots,
                       markY: [154, 201, 244, 285, 328, 371, 390], backTop: 152, backHeight: 242),
        meterOut: Meter(frame: CGRect(x: 1224, y: 148, width: 75, height: 251),
                        strips: [(1231, 1250), (1274, 1292)], slots: padSlots,
                        markY: [154, 201, 244, 285, 328, 371, 390], backTop: 152, backHeight: 242),
        screen: CGRect(x: 273, y: 128, width: 910, height: 258), scopeTextScale: 1,
        clip: CGRect(x: 591, y: 402, width: 266, height: 53), clipNumber: CGPoint(x: 738, y: 428), clipFont: 38,
        knobs: [
            Knob(param: .inputDB, center: CGPoint(x: 208.9, y: 581.5), pointerFrom: 34, pointerTo: 53, pointerWidth: 5,
                 value: CGRect(x: 138.9, y: 676, width: 140, height: 30), valueFont: 21, topic: .input),
            Knob(param: .driveDB, center: CGPoint(x: 465.4, y: 581.5), pointerFrom: 34, pointerTo: 53, pointerWidth: 5,
                 value: CGRect(x: 395.4, y: 676, width: 140, height: 30), valueFont: 21, topic: .drive),
            Knob(param: .ceilingDB, center: CGPoint(x: 723.4, y: 581.4), pointerFrom: 34, pointerTo: 53, pointerWidth: 5,
                 value: CGRect(x: 653.4, y: 676, width: 140, height: 30), valueFont: 21, topic: .ceiling),
            Knob(param: .mix, center: CGPoint(x: 983.1, y: 581.0), pointerFrom: 34, pointerTo: 53, pointerWidth: 5,
                 value: CGRect(x: 913.1, y: 676, width: 140, height: 30), valueFont: 21, topic: .mix),
            Knob(param: .outputDB, center: CGPoint(x: 1240.8, y: 581.8), pointerFrom: 34, pointerTo: 53, pointerWidth: 5,
                 value: CGRect(x: 1170.8, y: 676, width: 140, height: 30), valueFont: 21, topic: .output),
            Knob(param: .gold, center: CGPoint(x: 198.1, y: 795.8), pointerFrom: 17, pointerTo: 29, pointerWidth: 4,
                 value: CGRect(x: 162.1, y: 845, width: 72, height: 24), valueFont: 15, topic: .red),
            Knob(param: .alchemy, center: CGPoint(x: 677.6, y: 796.6), pointerFrom: 17, pointerTo: 29, pointerWidth: 4,
                 value: CGRect(x: 641.6, y: 845, width: 72, height: 24), valueFont: 15, topic: .fire)
        ],
        segments: [
            Segments(param: .goldMode, cells: [("MODERN", 282, 387), ("CLASSIC", 387, 490)], y: 758, h: 33, font: 14, topic: .redStyle),
            Segments(param: .boxTone, cells: [("FLAT", 820, 912), ("MODERN", 912, 1013), ("CLASSIC", 1013, 1116)], y: 792, h: 40, font: 14, topic: .boxTone),
            Segments(param: .clipMode, cells: [("HARD", 123, 243), ("CLASSIC", 243, 363), ("MODERN", 363, 486)], y: 922, h: 46, font: 16, topic: .clipMode),
            Segments(param: .oversampling, cells: [("1X", 767, 877), ("2X", 877, 982), ("4X", 982, 1093)], y: 922, h: 44, font: 16, topic: .oversampling)
        ],
        unity: Toggle(rect: CGRect(x: 312, y: 808, width: 152, height: 35), font: 15),
        link: Toggle(rect: CGRect(x: 567, y: 908, width: 123, height: 50), font: 17),
        delta: Toggle(rect: CGRect(x: 1180, y: 794, width: 133, height: 40), font: 16),
        bypass: Toggle(rect: CGRect(x: 1162, y: 907, width: 165, height: 51), font: 17),
        transport: Transport(play: CGRect(x: 65, y: 1012, width: 115, height: 45),
                             load: CGRect(x: 193, y: 1012, width: 115, height: 45),
                             samples: CGRect(x: 323, y: 1012, width: 145, height: 45),
                             demo: CGRect(x: 483, y: 1012, width: 107, height: 45),
                             fileName: CGRect(x: 607, y: 1022, width: 165, height: 24),
                             progress: CGRect(x: 790, y: 1019, width: 436, height: 30),
                             export: CGRect(x: 1251, y: 1012, width: 131, height: 45), font: 16),
        bubbleScale: 1)

    static let padSlots: [(CGFloat, CGFloat)] = [(154, 160), (166, 169), (175, 179), (183, 188), (193, 197), (202, 208),
        (210, 216), (220, 226), (229, 236), (240, 245), (250, 256), (260, 266), (270, 276), (281, 286),
        (291, 297), (301, 307), (312, 317), (322, 327), (332, 338), (342, 348), (353, 359), (362, 369),
        (373, 379), (383, 390)]

    // MARK: iPhone (851 x 1848, portrait, transport built into the picture)
    // Measured from the approved iPhone Face1 art (Red and Platinum share every position).

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
            Knob(param: .mix, center: CGPoint(x: 303.5, y: 1044), pointerFrom: 36, pointerTo: 56, pointerWidth: 6,
                 value: CGRect(x: 223, y: 1133, width: 160, height: 32), valueFont: 22, topic: .mix),
            Knob(param: .outputDB, center: CGPoint(x: 549.5, y: 1045.5), pointerFrom: 36, pointerTo: 56, pointerWidth: 6,
                 value: CGRect(x: 469.5, y: 1133, width: 160, height: 32), valueFont: 22, topic: .output),
            Knob(param: .gold, center: CGPoint(x: 182.2, y: 1262), pointerFrom: 16, pointerTo: 28, pointerWidth: 4,
                 value: CGRect(x: 142.5, y: 1306, width: 80, height: 27), valueFont: 17, topic: .red),
            Knob(param: .alchemy, center: CGPoint(x: 667.2, y: 1262), pointerFrom: 16, pointerTo: 28, pointerWidth: 4,
                 value: CGRect(x: 627.5, y: 1306, width: 80, height: 27), valueFont: 17, topic: .fire)
        ],
        segments: [
            Segments(param: .goldMode, cells: [("MODERN", 277, 392), ("CLASSIC", 392, 508)], y: 1214, h: 40, font: 16, topic: .redStyle),
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
}
