import Foundation

enum TypedStreamParser {
  static func messageText(_ text: String, attributedBody: Data) -> String {
    let decoded = text.isEmpty ? parseAttributedBody(attributedBody) : text
    return decoded.replacingOccurrences(of: "\u{FFFC}", with: "")
  }

  static func parseAttributedBody(_ data: Data) -> String {
    guard !data.isEmpty else { return "" }
    let bytes = [UInt8](data)
    let start = [UInt8(0x01), UInt8(0x2b)]
    let end = [UInt8(0x86), UInt8(0x84)]
    var best = ""
    let littleEndian = !data.starts(with: [0x04, 0x0b] + Array("typedstream".utf8))

    var index = 0
    while index + 1 < bytes.count {
      if bytes[index] == start[0], bytes[index + 1] == start[1] {
        let sliceStart = index + 2
        let range =
          stringRange(in: bytes, from: sliceStart, littleEndian: littleEndian)
          ?? findSequence(end, in: bytes, from: sliceStart).map { sliceStart..<$0 }
        if let range, let decoded = String(bytes: bytes[range], encoding: .utf8) {
          let candidate = decoded.trimmingLeadingControlCharacters()
          if candidate.count > best.count {
            best = candidate
          }
        }
      }
      index += 1
    }

    if !best.isEmpty {
      return best
    }

    // Never render a serialized archive as text when its payload could not be decoded.
    if data.starts(with: [0x04, 0x0b]) { return "" }
    let text = String(bytes: bytes, encoding: .utf8) ?? ""
    return text.trimmingLeadingControlCharacters()
  }

  private static func stringRange(in bytes: [UInt8], from start: Int, littleEndian: Bool)
    -> Range<Int>?
  {
    guard start < bytes.count else { return nil }
    let head = bytes[start]
    let width: Int
    switch head {
    case 0x81: width = 2
    case 0x82: width = 4
    case 0x80...0x8f: return nil
    default: width = 0
    }
    guard start + width < bytes.count else { return nil }
    var length = width == 0 ? Int(head) : 0
    for offset in 0..<width {
      let shift = littleEndian ? offset : width - offset - 1
      length |= Int(bytes[start + 1 + offset]) << (shift * 8)
    }
    let payloadStart = start + 1 + width
    guard length <= bytes.count - payloadStart else { return nil }
    let payloadEnd = payloadStart + length
    guard payloadEnd + 1 < bytes.count,
      bytes[payloadEnd] == 0x86, bytes[payloadEnd + 1] == 0x84
    else { return nil }
    return payloadStart..<payloadEnd
  }

  private static func findSequence(_ needle: [UInt8], in haystack: [UInt8], from start: Int)
    -> Int?
  {
    guard !needle.isEmpty else { return nil }
    guard start >= 0, start < haystack.count else { return nil }
    let limit = haystack.count - needle.count
    if limit < start { return nil }
    var index = start
    while index <= limit {
      var matched = true
      for offset in 0..<needle.count {
        if haystack[index + offset] != needle[offset] {
          matched = false
          break
        }
      }
      if matched { return index }
      index += 1
    }
    return nil
  }
}

extension String {
  fileprivate func trimmingLeadingControlCharacters() -> String {
    var scalars = unicodeScalars
    while let first = scalars.first,
      CharacterSet.controlCharacters.contains(first) || first == "\n" || first == "\r"
    {
      scalars.removeFirst()
    }
    return String(String.UnicodeScalarView(scalars))
  }
}
