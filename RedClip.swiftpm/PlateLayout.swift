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

    // MARK: iPhone (852 x 1847, portrait, transport built into the picture)

    static let phoneSlots: [(CGFloat, CGFloat)] = [(261, 266), (272, 278), (284, 289), (294, 299), (305, 310), (315, 321),
        (326, 332), (337, 344), (349, 355), (361, 367), (373, 379), (385, 391), (397, 403), (409, 415),
        (422, 428), (434, 440), (446, 452), (458, 464), (470, 476), (483, 489), (495, 501), (506, 513),
        (519, 526), (531, 538)]

    static let phone = PlateLayout(
        plate: "RCPhonePlate", segLit: "RCPhoneSegLit", segOff: "RCPhoneSegOff", abLit: "RCPhoneABLit", abOff: "RCPhoneABOff",
        size: CGSize(width: 852, height: 1847), canvas: CGSize(width: 852, height: 1847),
        strip: nil, pluginHeight: 1690,
        presetPrev: CGRect(x: 45, y: 125, width: 70, height: 62),
        presetNext: CGRect(x: 738, y: 125, width: 70, height: 62),
        presetName: CGRect(x: 120, y: 125, width: 612, height: 62), presetFont: 27,
        a: CGRect(x: 396, y: 31, width: 64, height: 59), b: CGRect(x: 460, y: 31, width: 64, height: 59),
        undo: CGRect(x: 556, y: 29, width: 66, height: 62), help: CGRect(x: 636, y: 29, width: 67, height: 63),
        power: CGRect(x: 718, y: 16, width: 76, height: 76),
        letterFont: 27, helpFont: 34, powerIcon: 34,
        meterIn: Meter(frame: CGRect(x: 26, y: 250, width: 78, height: 300),
                       strips: [(30, 57), (74, 100)], slots: phoneSlots,
                       markY: [259, 310, 360, 409, 458, 507, 556], backTop: 255, backHeight: 290),
        meterOut: Meter(frame: CGRect(x: 708, y: 250, width: 79, height: 300),
                        strips: [(712, 739), (757, 783)], slots: phoneSlots,
                        markY: [259, 310, 360, 409, 458, 507, 556], backTop: 255, backHeight: 290),
        screen: CGRect(x: 168, y: 212, width: 517, height: 318), scopeTextScale: 1.25,
        clip: CGRect(x: 288, y: 547, width: 275, height: 59), clipNumber: CGPoint(x: 431, y: 577), clipFont: 44,
        knobs: [
            Knob(param: .inputDB, center: CGPoint(x: 154.4, y: 760.3), pointerFrom: 38, pointerTo: 63, pointerWidth: 6,
                 value: CGRect(x: 74.4, y: 862, width: 160, height: 34), valueFont: 25, topic: .input),
            Knob(param: .driveDB, center: CGPoint(x: 425.7, y: 760.2), pointerFrom: 38, pointerTo: 63, pointerWidth: 6,
                 value: CGRect(x: 345.7, y: 862, width: 160, height: 34), valueFont: 25, topic: .drive),
            Knob(param: .ceilingDB, center: CGPoint(x: 702.2, y: 760.4), pointerFrom: 38, pointerTo: 63, pointerWidth: 6,
                 value: CGRect(x: 622.2, y: 862, width: 160, height: 34), valueFont: 25, topic: .ceiling),
            Knob(param: .mix, center: CGPoint(x: 288.2, y: 1020.9), pointerFrom: 38, pointerTo: 63, pointerWidth: 6,
                 value: CGRect(x: 208.2, y: 1123, width: 160, height: 34), valueFont: 25, topic: .mix),
            Knob(param: .outputDB, center: CGPoint(x: 565.7, y: 1022.9), pointerFrom: 38, pointerTo: 63, pointerWidth: 6,
                 value: CGRect(x: 485.7, y: 1123, width: 160, height: 34), valueFont: 25, topic: .output),
            Knob(param: .gold, center: CGPoint(x: 153.1, y: 1265.6), pointerFrom: 18, pointerTo: 31, pointerWidth: 4.5,
                 value: CGRect(x: 113.1, y: 1316, width: 80, height: 30), valueFont: 20, topic: .red),
            Knob(param: .alchemy, center: CGPoint(x: 698.2, y: 1266.1), pointerFrom: 18, pointerTo: 31, pointerWidth: 4.5,
                 value: CGRect(x: 658.2, y: 1316, width: 80, height: 30), valueFont: 20, topic: .fire)
        ],
        segments: [
            Segments(param: .goldMode, cells: [("MODERN", 259, 391), ("CLASSIC", 391, 519)], y: 1214, h: 44, font: 18, topic: .redStyle),
            Segments(param: .boxTone, cells: [("FLAT", 68, 204), ("MODERN", 204, 343), ("CLASSIC", 343, 481)], y: 1407, h: 51, font: 18, topic: .boxTone),
            Segments(param: .clipMode, cells: [("HARD", 107, 320), ("CLASSIC", 320, 535), ("MODERN", 535, 746)], y: 1519, h: 47, font: 18, topic: .clipMode),
            Segments(param: .oversampling, cells: [("1X", 254, 373), ("2X", 373, 481), ("4X", 481, 600)], y: 1623, h: 47, font: 18, topic: .oversampling)
        ],
        unity: Toggle(rect: CGRect(x: 297, y: 1281, width: 190, height: 47), font: 18),
        link: Toggle(rect: CGRect(x: 36, y: 1608, width: 159, height: 56), font: 22),
        delta: Toggle(rect: CGRect(x: 596, y: 1409, width: 180, height: 48), font: 21),
        bypass: Toggle(rect: CGRect(x: 658, y: 1608, width: 160, height: 56), font: 18),
        transport: Transport(play: CGRect(x: 42, y: 1698, width: 177, height: 62),
                             load: CGRect(x: 228, y: 1698, width: 180, height: 64),
                             samples: CGRect(x: 417, y: 1698, width: 205, height: 66),
                             demo: CGRect(x: 631, y: 1698, width: 181, height: 62),
                             fileName: CGRect(x: 66, y: 1782, width: 160, height: 28),
                             progress: CGRect(x: 240, y: 1780, width: 340, height: 30),
                             export: CGRect(x: 622, y: 1767, width: 168, height: 59), font: 20),
        bubbleScale: 1.9)
}
