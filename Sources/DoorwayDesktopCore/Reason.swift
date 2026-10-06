import Foundation

/// Words needed before a reason is accepted. Hardcoded on purpose.
public let minimumWords = 10

/// Words = whitespace-separated tokens, nothing else.
public func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}

/// 1st, 2nd, 3rd, 4th, 11th, 21st... for the "(3rd)" after the prompt's question.
public func ordinal(_ n: Int) -> String {
    let suffix: String
    switch (n % 10, n % 100) {
    case (_, 11...13): suffix = "th"
    case (1, _): suffix = "st"
    case (2, _): suffix = "nd"
    case (3, _): suffix = "rd"
    default: suffix = "th"
    }
    return "\(n)\(suffix)"
}
