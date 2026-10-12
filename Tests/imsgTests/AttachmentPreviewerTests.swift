import CoreGraphics
import Foundation
import IMsgCore
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import imsg

@Test
func heicPreviewDecodesDirectlyToBrowserSafePNG() async throws {
  let context = try #require(
    CGContext(
      data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
  context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
  let image = try #require(context.makeImage())
  let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("fixture.heic")
  let destination = try #require(
    CGImageDestinationCreateWithURL(
      file as CFURL, UTType.heic.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  let meta = AttachmentMeta(
    rowID: 1, filename: file.path, transferName: "fixture.heic", uti: "public.heic",
    mimeType: "image/heic", totalBytes: 0, isSticker: false, originalPath: file.path, missing: false
  )
  let preview = try await AttachmentPreviewer.previewData(for: meta)
  #expect(preview.mimeType == "image/png")
  #expect(Array(preview.data.prefix(8)) == [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
  let source = try #require(CGImageSourceCreateWithData(preview.data as CFData, nil))
  let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  #expect(decoded.width == 32)
  #expect(decoded.height == 24)
}
