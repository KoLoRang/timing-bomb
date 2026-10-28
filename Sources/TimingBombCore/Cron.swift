import Foundation

/// Matching and next-fire computation for 5-field cron expressions (minute hour day-of-month month day-of-week).
/// Field syntax supports `*`, `*/n`, `a`, `a-b`, `a-b/n`, comma-separated lists,
/// weekday name abbreviations (sun...sat), and aliases like @daily/@hourly.
public enum CronMatcher {
    public struct Fields: Sendable {
        public var minute: Set<Int>
        public var hour: Set<Int>
        public var dayOfMonth: Set<Int>
        public var month: Set<Int>
        public var dayOfWeek: Set<Int>

        var domRestricted: Bool { dayOfMonth.count < 31 }
        var dowRestricted: Bool { dayOfWeek.count < 7 }
    }

    public static func fields(_ expression: String) -> Fields? {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        let expanded = CronSyntax.alias(for: expr) ?? expr
        let parts = expanded.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return nil }
        guard
            let minute = parseField(parts[0], range: 0...59),
            let hour = parseField(parts[1], range: 0...23),
            let dom = parseField(parts[2], range: 1...31),
            let month = parseField(parts[3], range: 1...12),
            var dow = parseField(parts[4], range: 0...6, allowNames: true)
        else { return nil }
        // 7 also means Sunday
        if dow.contains(7) {
            dow.insert(0)
            dow.remove(7)
        }
        return Fields(
            minute: minute, hour: hour, dayOfMonth: dom, month: month, dayOfWeek: dow)
    }

    public static func matches(
        _ expression: String, at date: Date, timeZone: TimeZone = .current
    ) -> Bool {
        guard let fields = fields(expression) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.minute, .hour, .day, .month, .weekday], from: date)
        guard
            let minute = components.minute, let hour = components.hour,
            let day = components.day, let month = components.month,
            let weekday = components.weekday
        else { return false }
        let dow = weekday - 1  // Calendar Sunday=1..Saturday=7 → cron Sunday=0..Saturday=6

        // Standard cron semantics: when both dom and dow are restricted, they match by OR
        let dayMatches: Bool
        if fields.domRestricted && fields.dowRestricted {
            dayMatches = fields.dayOfMonth.contains(day) || fields.dayOfWeek.contains(dow)
        } else {
            dayMatches = fields.dayOfMonth.contains(day) && fields.dayOfWeek.contains(dow)
        }
        return fields.minute.contains(minute) && fields.hour.contains(hour)
            && fields.month.contains(month) && dayMatches
    }

    /// The next matching moment after `date` (minute granularity); limit guards against pathological expressions searching forever.
    public static func nextFire(
        after date: Date, expression: String, timeZone: TimeZone = .current,
        limit: Date? = nil
    ) -> Date? {
        guard fields(expression) != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var candidate = calendar.dateInterval(of: .minute, for: date)?.end ?? date
        candidate = candidate.addingTimeInterval(60)
        let deadline = limit ?? date.addingTimeInterval(366 * 24 * 3600)
        while candidate <= deadline {
            if matches(expression, at: candidate, timeZone: timeZone) {
                return candidate
            }
            candidate = candidate.addingTimeInterval(60)
        }
        return nil
    }

    /// Parses a single field into a set of matching values; nil means invalid syntax.
    static func parseField(
        _ field: String, range: ClosedRange<Int>, allowNames: Bool = false
    ) -> Set<Int>? {
        var result = Set<Int>()
        for part in field.split(separator: ",") {
            let piece = String(part)
            if piece == "*" {
                result.formUnion(range)
                continue
            }
            if piece.hasPrefix("*/") {
                guard let step = Int(piece.dropFirst(2)), step > 0 else { return nil }
                result.formUnion(stride(from: range.lowerBound, through: range.upperBound, by: step))
                continue
            }
            var lowText = piece
            var highText: String? = nil
            var step = 1
            if let slash = piece.firstIndex(of: "/") {
                guard let parsed = Int(piece[piece.index(after: slash)...]), parsed > 0 else { return nil }
                step = parsed
                lowText = String(piece[..<slash])
            }
            if let dash = lowText.firstIndex(of: "-") {
                highText = String(lowText[lowText.index(after: dash)...])
                lowText = String(lowText[..<dash])
            }
            guard let low = number(lowText, range: range, allowNames: allowNames) else { return nil }
            if let highText {
                guard let high = number(highText, range: range, allowNames: allowNames) else { return nil }
                guard low <= high else { return nil }
                result.formUnion(stride(from: low, through: high, by: step))
            } else {
                guard range.contains(low) else { return nil }
                if step == 1 {
                    result.insert(low)
                } else {
                    result.formUnion(
                        stride(from: low, through: range.upperBound, by: step))
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func number(_ token: String, range: ClosedRange<Int>, allowNames: Bool) -> Int? {
        if let value = Int(token) { return value }
        if allowNames, let index = CronSyntax.dayNames.firstIndex(of: token.lowercased()) {
            return index
        }
        return nil
    }
}
