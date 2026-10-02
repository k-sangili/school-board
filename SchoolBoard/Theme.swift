import SwiftUI

enum Theme {
    static let background = Color(hex: "#0B0E13")
    static let panel = Color(hex: "#151A22")
    static let panelRaised = Color(hex: "#1D2430")
    static let text = Color(hex: "#F1F4F9")
    static let secondary = Color(hex: "#98A2B3")
    static let today = Color(hex: "#FFD166")
    static let test = Color(hex: "#FF6B6B")
    static let deadline = Color(hex: "#FFB547")
    static let noSchool = Color(hex: "#3DD68C")

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt64(digits, radix: 16) ?? 0x98A2B3
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
