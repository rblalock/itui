import Foundation
import Testing

@testable import imsg

@Test
func omarchyThemeStorePersistsPaletteAndRejectsInvalidReplacement() async throws {
  let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("theme.json")
  let store = OmarchyThemeStore(fileURL: file)
  let theme = OmarchyTheme(
    name: "Dusk",
    colors: [
      "accent": "#8fb1d7", "background": "#0e1720", "foreground": "#d5ceb1",
      "green": "#a7c8a5", "mode": "dark",
    ])
  try await store.update(theme)
  #expect(await store.current() == theme)
  #expect(await OmarchyThemeStore(fileURL: file).current() == theme)
  do {
    try await store.update(OmarchyTheme(name: "Bad", colors: ["accent": "red"]))
    #expect(Bool(false))
  } catch {
    #expect(await store.current() == theme)
    #expect(await OmarchyThemeStore(fileURL: file).current() == theme)
  }
}
