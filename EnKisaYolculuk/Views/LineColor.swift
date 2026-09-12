import SwiftUI

extension Color {
    /// Parses "#RRGGBB" / "RRGGBB" from the data file. Falls back to a neutral
    /// accent when the field is missing or malformed, so bad data never
    /// crashes the UI.
    init(lineHex hex: String?) {
        guard let hex else { self = .accentColor; return }
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .accentColor
            return
        }
        self = Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue:  Double(value & 0xFF) / 255
        )
    }
}

extension Line {
    var color: Color { Color(lineHex: colorHex) }
}

/// Small rounded badge showing a line id in its own colour.
struct LineBadge: View {
    let line: Line
    var size: CGFloat = 15

    var body: some View {
        Text(line.id)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(line.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
