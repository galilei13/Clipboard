import AppKit

public enum ClipColor {
    public static func parse(_ text: String) -> NSColor? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            var hex = String(value.dropFirst())
            guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy({ $0.isHexDigit }) else { return nil }
            if hex.count <= 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let bits = UInt64(hex, radix: 16) else { return nil }
            let alpha = hex.count == 8 ? Double(bits & 255) / 255 : 1
            let rgb = hex.count == 8 ? bits >> 8 : bits
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: alpha)
        }
        let lower = value.lowercased()
        guard (lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(")), lower.hasSuffix(")"),
              let start = lower.firstIndex(of: "(") else { return nil }
        let parts = lower[lower.index(after: start)..<lower.index(before: lower.endIndex)]
            .split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == (lower.hasPrefix("rgba") ? 4 : 3) else { return nil }
        var channels: [Double] = []
        for part in parts.prefix(3) {
            let percent = part.hasSuffix("%")
            guard let number = Double(percent ? String(part.dropLast()) : part), (0...(percent ? 100.0 : 255.0)).contains(number) else { return nil }
            channels.append(number / (percent ? 100 : 255))
        }
        let alpha = parts.count == 4 ? Double(parts[3]) : 1
        guard let alpha, (0...1).contains(alpha) else { return nil }
        return NSColor(srgbRed: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }
}
