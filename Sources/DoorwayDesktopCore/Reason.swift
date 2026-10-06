import Foundation

/// Words needed before a reason is accepted. Hardcoded on purpose.
public let minimumWords = 10

/// Words = whitespace-separated tokens, nothing else.
public func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}
