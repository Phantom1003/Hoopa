import Foundation

/// Fuzzy matching of window / element titles. Score 0…1.
enum TitleMatch {
    private static let separators = [" — ", " – ", " - ", " | ", " · ", " • ", " › ", " > "]

    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func segments(_ s: String) -> [String] {
        var parts = [s]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return parts.map(normalize).filter { !$0.isEmpty }
    }

    private static func bigrams(_ s: String) -> Set<String> {
        let chars = Array(s.filter { !$0.isWhitespace })
        guard chars.count >= 2 else { return chars.isEmpty ? [] : [String(chars)] }
        var set = Set<String>()
        for i in 0..<(chars.count - 1) { set.insert(String(chars[i...i + 1])) }
        return set
    }

    static func score(_ a: String, _ b: String) -> Double {
        let x = normalize(a), y = normalize(b)
        if x.isEmpty || y.isEmpty { return 0 }
        if x == y { return 1 }
        if x.contains(y) || y.contains(x) {
            let ratio = Double(min(x.count, y.count)) / Double(max(x.count, y.count))
            return 0.6 + 0.3 * ratio
        }
        let sx = Set(segments(x)), sy = Set(segments(y))
        let common = sx.intersection(sy).count
        if common > 0 {
            return 0.45 + 0.3 * Double(common) / Double(max(sx.count, sy.count))
        }
        let bx = bigrams(x), by = bigrams(y)
        let union = bx.union(by).count
        guard union > 0 else { return 0 }
        return 0.6 * Double(bx.intersection(by).count) / Double(union)
    }
}
