extension StringProtocol {
  /// The text without leading and trailing whitespace or line breaks.
  var trimmedWhitespace: SubSequence {
    guard let first = firstIndex(where: { !$0.isWhitespace }),
      let last = lastIndex(where: { !$0.isWhitespace })
    else { return self[startIndex..<startIndex] }
    return self[first...last]
  }

  /// The value of an unsigned number written only with ASCII digits, or `nil` for any other text.
  /// A value above `limit` reads as `limit + 1`, so a long digit string never overflows.
  func asciiNumber(limit: Int) -> Int? {
    var value = 0
    for byte in utf8 {
      guard (0x30...0x39).contains(byte) else { return nil }
      value = Swift.min(value * 10 + Int(byte - 0x30), limit + 1)
    }
    return value
  }
}
