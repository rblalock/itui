import Foundation
import Testing

@testable import IMsgCore

@Test
func attributedBodyDecodesExtendedLengthsWithoutGarbage() {
  let text = String(repeating: "a", count: 147)
  let body = Data([0x01, 0x2b, 0x81, 0x93, 0x00] + Array(text.utf8) + [0x86, 0x84])
  #expect(TypedStreamParser.parseAttributedBody(body) == text)
}

@Test
func attributedBodyDecodesFourByteAndBigEndianLengths() {
  let text = String(repeating: "b", count: 300)
  let little = Data([0x01, 0x2b, 0x82, 0x2c, 0x01, 0x00, 0x00] + Array(text.utf8) + [0x86, 0x84])
  let big = Data(
    [0x04, 0x0b] + Array("typedstream".utf8) + [0x01, 0x2b, 0x81, 0x01, 0x2c]
      + Array(text.utf8) + [0x86, 0x84])
  #expect(TypedStreamParser.parseAttributedBody(little) == text)
  #expect(TypedStreamParser.parseAttributedBody(big) == text)
}

@Test
func attributedBodyUsesByteLengthForUnicodeAndEmbeddedDelimiter() {
  let text = "Photo \u{1184} 🙂"
  let body = Data([0x01, 0x2b, UInt8(text.utf8.count)] + Array(text.utf8) + [0x86, 0x84])
  #expect(TypedStreamParser.parseAttributedBody(body) == text)
}

@Test
func messageTextRemovesAttachmentPlaceholdersAndPreservesCaption() {
  #expect(
    TypedStreamParser.messageText("\u{FFFC}\u{FFFC}Here are the photos", attributedBody: Data())
      == "Here are the photos")
  let body = Data([0x01, 0x2b, 3, 0xef, 0xbf, 0xbc, 0x86, 0x84])
  #expect(TypedStreamParser.messageText("", attributedBody: body).isEmpty)
}

@Test
func invalidArchiveDoesNotBecomeGarbageText() {
  let body = Data([0x04, 0x0b] + Array("streamtyped".utf8) + [0x01, 0x2b, 0x81, 0xff])
  #expect(TypedStreamParser.parseAttributedBody(body).isEmpty)
}
