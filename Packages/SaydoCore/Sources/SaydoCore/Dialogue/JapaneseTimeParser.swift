import Foundation

/// M3「今日は何時に、どこでやる？」の答えを、時刻と場所に分ける（実装計画 §7.2 M3、retention R11）。
///
/// 時計は持たない。基準時刻とカレンダーは呼び出し側が渡す。
/// 場所は解釈せず、時刻の語を取り除いた残りを**本人の言葉のまま**返す。
public struct JapaneseTimeParser: Sendable {

    /// 解析の結果。
    public struct Result: Sendable, Equatable {
        /// 解釈できた時刻。できなければ nil（会話は止めない）。
        public var date: Date?
        /// 場所（本人の言葉のまま）。読み取れなければ空文字。
        public var place: String
        /// 時刻として読み取った語。
        public var matchedPhrase: String?

        public init(date: Date? = nil, place: String = "", matchedPhrase: String? = nil) {
            self.date = date
            self.place = place
            self.matchedPhrase = matchedPhrase
        }
    }

    /// 時刻の語を持たない言い回し（「夕方」など）と、それが指す時刻。
    public static let namedTimes: [(phrase: String, hour: Int, minute: Int)] = [
        ("お昼過ぎ", 13, 0),
        ("昼過ぎ", 13, 0),
        ("午前中", 10, 0),
        ("お昼", 12, 0),
        ("夕方", 17, 0),
        ("午前", 9, 0),
        ("午後", 14, 0),
        ("朝", 8, 0),
        ("昼", 12, 0),
        ("夜", 20, 0),
    ]

    public init() {}

    /// 「14時に自宅で」のような答えを時刻と場所に分ける。
    public func parse(_ text: String, now: Date, calendar: Calendar = .current) -> Result {
        let normalized = Self.normalizeDigits(text)

        if let relative = parseRelative(normalized, now: now) {
            return result(normalized: normalized, matched: relative.phrase, date: relative.date)
        }
        if let clock = parseClock(normalized, now: now, calendar: calendar) {
            return result(normalized: normalized, matched: clock.phrase, date: clock.date)
        }
        if let named = parseNamed(normalized, now: now, calendar: calendar) {
            return result(normalized: normalized, matched: named.phrase, date: named.date)
        }
        return Result(date: nil, place: Self.trimParticles(text), matchedPhrase: nil)
    }

    // MARK: - 相対時刻（「1時間後」「30分後」）

    private func parseRelative(_ text: String, now: Date) -> (phrase: String, date: Date)? {
        if let range = text.range(of: "[0-9]+時間半後", options: .regularExpression) {
            let phrase = String(text[range])
            let hours = Self.firstNumber(in: phrase) ?? 0
            return (phrase, now.addingTimeInterval(Double(hours) * 3600 + 1800))
        }
        if let range = text.range(of: "[0-9]+時間後", options: .regularExpression) {
            let phrase = String(text[range])
            let hours = Self.firstNumber(in: phrase) ?? 0
            return (phrase, now.addingTimeInterval(Double(hours) * 3600))
        }
        if let range = text.range(of: "[0-9]+分後", options: .regularExpression) {
            let phrase = String(text[range])
            let minutes = Self.firstNumber(in: phrase) ?? 0
            return (phrase, now.addingTimeInterval(Double(minutes) * 60))
        }
        return nil
    }

    // MARK: - 時計時刻（「14時」「2時半」「午後2時30分」）

    private func parseClock(_ text: String, now: Date, calendar: Calendar) -> (phrase: String, date: Date)? {
        guard let range = text.range(of: "(午前|午後)?[0-9]+時((半)|([0-9]+分))?", options: .regularExpression) else {
            return nil
        }
        let phrase = String(text[range])
        guard let hour = Self.firstNumber(in: phrase) else { return nil }

        var minute = 0
        if phrase.contains("半") {
            minute = 30
        } else if let minuteRange = phrase.range(of: "[0-9]+分", options: .regularExpression) {
            minute = Self.firstNumber(in: String(phrase[minuteRange])) ?? 0
        }

        let meridiem: Bool? = phrase.hasPrefix("午後") ? true : (phrase.hasPrefix("午前") ? false : nil)
        guard let date = Self.resolve(hour: hour, minute: minute, isPM: meridiem, now: now, calendar: calendar) else {
            return nil
        }
        return (phrase, date)
    }

    // MARK: - 言い回し（「昼過ぎ」「夕方」）

    private func parseNamed(_ text: String, now: Date, calendar: Calendar) -> (phrase: String, date: Date)? {
        for named in Self.namedTimes where text.contains(named.phrase) {
            guard let date = Self.resolve(
                hour: named.hour,
                minute: named.minute,
                isPM: named.hour >= 12,
                now: now,
                calendar: calendar
            ) else { continue }
            return (named.phrase, date)
        }
        return nil
    }

    // MARK: - 場所

    private func result(normalized: String, matched: String, date: Date) -> Result {
        // 全角数字を直した文から時刻の語を取り除き、残りを場所として本人の言葉のまま返す。
        let remainder = normalized.replacingOccurrences(of: matched, with: "")
        return Result(date: date, place: Self.trimParticles(remainder), matchedPhrase: matched)
    }

    /// 助詞と言い回しだけを落とす。語そのものは書き換えない。
    static func trimParticles(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let leading: Set<Character> = ["に", "は", "の", "、", "，", "。", " ", "　"]
        let trailingPhrases = ["でやります", "でやろう", "でやる", "でします", "でやりたい", "します", "やります", "やる"]
        let trailing: Set<Character> = ["で", "に", "は", "、", "，", "。", " ", "　"]

        var changed = true
        while changed {
            changed = false
            while let first = value.first, leading.contains(first) {
                value.removeFirst()
                changed = true
            }
            for phrase in trailingPhrases where value.hasSuffix(phrase) {
                value.removeLast(phrase.count)
                changed = true
                break
            }
            while let last = value.last, trailing.contains(last) {
                value.removeLast()
                changed = true
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 補助

    /// 全角数字を半角にする。
    static func normalizeDigits(_ text: String) -> String {
        String(text.map { character in
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1,
                  (0xFF10...0xFF19).contains(scalar.value),
                  let ascii = Unicode.Scalar(scalar.value - 0xFF10 + 0x30)
            else { return character }
            return Character(ascii)
        })
    }

    static func firstNumber(in text: String) -> Int? {
        guard let range = text.range(of: "[0-9]+", options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    /// 時刻を今日か明日の `Date` に落とす。
    ///
    /// 「2時」のように午前か午後かが分からない場合は、今日これから来る方（2 時 → 14 時）を選び、
    /// 今日にもう来ないなら翌日の同じ時刻にする。
    static func resolve(hour: Int, minute: Int, isPM: Bool?, now: Date, calendar: Calendar) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        func makeDate(hour: Int, dayOffset: Int) -> Date? {
            guard let base = calendar.date(byAdding: .day, value: dayOffset, to: now) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
        }

        switch isPM {
        case .some(true):
            return makeDate(hour: hour % 12 + 12, dayOffset: 0)
        case .some(false):
            return makeDate(hour: hour % 12, dayOffset: 0)
        case .none:
            if hour >= 13 { return makeDate(hour: hour, dayOffset: 0) }
            let candidates = [hour, hour + 12]
                .filter { (0...23).contains($0) }
                .compactMap { makeDate(hour: $0, dayOffset: 0) }
                .filter { $0 > now }
                .sorted()
            return candidates.first ?? makeDate(hour: hour, dayOffset: 1)
        }
    }
}
