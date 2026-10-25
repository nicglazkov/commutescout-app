import Foundation

/// The text rules applied before Kokoro speaks. Kokoro reads words
/// through its lexicons only and has no rules for numbers or
/// abbreviations, so route numbers, street abbreviations and digits are
/// spelled out first. A port of `scripts/voices/norm.py`, kept
/// rule-for-rule the same, in this order: abbreviations, route numbers,
/// ordinals (3rd "third"), decimals, letters then digits (G5 "G five"),
/// digits then a letter (5A "five A"), then any other number. Supertonic
/// reads raw text and never goes through this.
enum KokoroText {
    private static let ones = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen"
        .split(separator: " ").map(String.init)
    private static let tens = "_ _ twenty thirty forty fifty sixty seventy eighty ninety"
        .split(separator: " ").map(String.init)

    static func words(_ n: Int) -> String {
        if n < 20 { return ones[n] }
        if n < 100 { return tens[n / 10] + (n % 10 == 0 ? "" : " " + ones[n % 10]) }
        if n < 1000 { return ones[n / 100] + " hundred" + (n % 100 == 0 ? "" : " " + words(n % 100)) }
        if n < 1_000_000 { return words(n / 1000) + " thousand" + (n % 1000 == 0 ? "" : " " + words(n % 1000)) }
        return String(n).map { ones[Int(String($0))!] }.joined(separator: " ")
    }

    /// Road numbers the way drivers say them: 101 "one oh one", 80
    /// "eighty", 405 "four oh five".
    static func routeNumber(_ s: String) -> String {
        let digits = s.map { Int(String($0)) ?? 0 }
        let i = Int(s) ?? 0
        if i < 100 { return words(i) }
        if digits.count == 3, digits[1] == 0 { return ones[digits[0]] + " oh " + ones[digits[2]] }
        if digits.count == 3 { return ones[digits[0]] + " " + words(Int(s.dropFirst()) ?? 0) }
        return words(i)
    }

    private static let prefix = ["I": "I", "US": "U S", "CA": "C A", "SR": "State Route", "Hwy": "Highway",
                                 "Highway": "Highway", "Route": "Route", "Interstate": "Interstate"]
    /// In the reference's order: the order matters where one rule's
    /// output could feed another.
    private static let abbreviations: [(String, String)] = [
        (#"\bSt\b"#, "Street"), (#"\bAve\b"#, "Avenue"), (#"\bBlvd\b"#, "Boulevard"), (#"\bRd\b"#, "Road"),
        (#"\bDr\b"#, "Drive"), (#"\bN\b"#, "North"), (#"\bS\b"#, "South"), (#"\bE\b"#, "East"), (#"\bW\b"#, "West"),
        (#"\bmph\b"#, "miles per hour"), (#"\bCHP\b"#, "C H P"), (#"\bmi\b"#, "miles"), (#"\bkm\b"#, "kilometers"),
        (#"\bft\b"#, "feet"),
    ]
    private static let abbreviationPatterns = abbreviations.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    private static let route = try! NSRegularExpression(pattern: #"\b(I|US|CA|SR|Hwy|Highway|Route|Interstate)[- ]?(\d{1,3})\b"#)
    private static let ordinalNumber = try! NSRegularExpression(pattern: #"\b(\d+)(st|nd|rd|th)\b"#)
    private static let decimal = try! NSRegularExpression(pattern: #"(\d+)\.(\d+)"#)
    private static let lettersDigits = try! NSRegularExpression(pattern: #"\b([A-Za-z]+)(\d+)\b"#)
    private static let digitsLetter = try! NSRegularExpression(pattern: #"\b(\d+)([A-Za-z])\b"#)
    private static let integer = try! NSRegularExpression(pattern: #"\d+"#)

    private static let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth",
                                    "eight": "eighth", "nine": "ninth", "twelve": "twelfth"]

    /// 3 "third", 21 "twenty first", 112 "one hundred twelfth", 40 "fortieth".
    static func ordinal(_ n: Int) -> String {
        var w = words(n).split(separator: " ").map(String.init)
        let last = w[w.count - 1]
        w[w.count - 1] = irregular[last] ?? (last.hasSuffix("y") ? String(last.dropLast()) + "ieth" : last + "th")
        return w.joined(separator: " ")
    }

    /// An all-caps run of one to three letters is spelled out: "AB" "A B".
    private static func letters(_ s: String) -> String {
        (1 ... 3).contains(s.count) && s == s.uppercased() ? s.map(String.init).joined(separator: " ") : s
    }

    static func normalize(_ input: String) -> String {
        var t = input
        for (re, word) in abbreviationPatterns {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t),
                                            withTemplate: NSRegularExpression.escapedTemplate(for: word))
        }
        t = replace(route, in: t) { g in prefix[g[1]]! + " " + routeNumber(g[2]) }
        t = replace(ordinalNumber, in: t) { g in ordinal(Int(g[1]) ?? 0) }
        t = replace(decimal, in: t) { g in
            words(Int(g[1]) ?? 0) + " point " + g[2].map { ones[Int(String($0)) ?? 0] }.joined(separator: " ")
        }
        t = replace(lettersDigits, in: t) { g in letters(g[1]) + " " + words(Int(g[2]) ?? 0) }
        t = replace(digitsLetter, in: t) { g in words(Int(g[1]) ?? 0) + " " + g[2] }
        t = replace(integer, in: t) { g in words(Int(g[0]) ?? 0) }
        return t
    }

    /// Every match of `re` replaced by `make(groups)`, left to right, the
    /// way Python's re.sub does it.
    private static func replace(_ re: NSRegularExpression, in s: String, _ make: ([String]) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0 ..< m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            out += make(groups)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// The words Kokoro would look up, lowercased: runs of letters and
    /// apostrophes, with apostrophes trimmed from the ends.
    static func lookupWords(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0 == "'" || $0 == "\u{2019}") }
            .map { $0.replacingOccurrences(of: "\u{2019}", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// Words of already normalized text that neither lexicon has. Kokoro
    /// skips such a word without a sound, so a sentence with one is said
    /// by the system voice instead.
    static func unknownWords(_ normalized: String, known: (String) -> Bool) -> [String] {
        var out: [String] = []
        for w in lookupWords(normalized) where !known(w) && !out.contains(w) { out.append(w) }
        return out
    }
}
