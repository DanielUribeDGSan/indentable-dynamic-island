import SwiftUI

enum IslandMetrics {
    static let shadowPad: CGFloat = 48
    static let open = Animation.spring(duration: 0.32, bounce: 0.08)
    static let close = Animation.spring(duration: 0.28, bounce: 0.05)
    static let canvas = CGSize(width: 540 + shadowPad * 2, height: 620 + shadowPad * 2)
}

enum IslandPalette {
    static let ink = Color(hex: 0x181818)
    static let graphite = Color(hex: 0x383838)
    static let ash = Color(hex: 0x585858)
    static let stone = Color(hex: 0x787878)
    static let mist = Color(hex: 0x989898)
    static let silver = Color(hex: 0xB8B8B8)
    static let cloud = Color(hex: 0xD8D8D8)
    static let paper = Color(hex: 0xF8F8F8)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct IslandShape: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(radius, min(rect.width, rect.height) / 2), style: .continuous)
            .path(in: rect)
    }
}

