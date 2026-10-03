import Foundation

struct OmarchyTheme: Codable, Sendable, Equatable {
  let name: String
  let colors: [String: String]
}

/// One palette published by the Linux desktop; each browser chooses whether to follow it.
actor OmarchyThemeStore {
  private let fileURL: URL
  private var theme: OmarchyTheme?

  init(
    fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/itui/omarchy-theme.json")
  ) {
    self.fileURL = fileURL
    if let data = try? Data(contentsOf: fileURL),
      let saved = try? JSONDecoder().decode(OmarchyTheme.self, from: data),
      Self.isValid(saved)
    {
      theme = saved
    }
  }

  func current() -> OmarchyTheme? { theme }

  func update(_ next: OmarchyTheme) throws {
    guard Self.isValid(next) else {
      throw CocoaError(.validationMissingMandatoryProperty)
    }
    guard theme != next else { return }
    let data = try JSONEncoder().encode(next)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
    theme = next
  }

  static func isValid(_ theme: OmarchyTheme) -> Bool {
    guard !theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      theme.name.count <= 120,
      ["accent", "background", "foreground"].allSatisfy({ theme.colors[$0] != nil })
    else { return false }
    let allowed: Set<String> = [
      "accent", "background", "foreground", "selection", "selection_background",
      "selection_foreground", "red", "green", "yellow", "blue", "magenta", "cyan",
      "color1", "color2", "color3", "color4", "color5", "color6", "mode",
    ]
    return theme.colors.allSatisfy { key, value in
      guard allowed.contains(key) else { return false }
      if key == "mode" { return value == "dark" || value == "light" }
      return value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }
  }
}
