import Foundation

/// A handle (phone/email) enriched with contact data from the local Contacts store.
///
/// `ResolvedContact` is the canonical contact representation used across every public API
/// surface (HTTP, WebSocket, JSON-RPC, CLI). It is designed so clients can render a
/// messaging UI without additional round trips: `name` provides a display name, `initials`
/// a fallback glyph, and three parallel avatar delivery modes cover browser, native, and
/// embedded consumers:
///
/// * `avatarURL` — a relative HTTP URL such as `/api/contacts/avatar?handle=...` that the
///   web server can stream directly. Nil unless served from the embedded HTTP API.
/// * `avatarPath` — an absolute filesystem path into the on-disk cache. Nil when there is
///   no avatar to serve.
/// * `avatarBase64` — the image bytes encoded as base64. Emitted only when a caller asks
///   for inline delivery to avoid bloating list responses.
public struct ResolvedContact: Sendable, Equatable, Codable {
  public let handle: String
  public let name: String?
  public let initials: String
  public let hasAvatar: Bool
  public let avatarMime: String?
  public let avatarPath: String?
  public let avatarURL: String?
  public let avatarBase64: String?
  public let avatarBytes: Int

  public init(
    handle: String,
    name: String? = nil,
    initials: String = "",
    hasAvatar: Bool = false,
    avatarMime: String? = nil,
    avatarPath: String? = nil,
    avatarURL: String? = nil,
    avatarBase64: String? = nil,
    avatarBytes: Int = 0
  ) {
    self.handle = handle
    self.name = name
    self.initials = initials
    self.hasAvatar = hasAvatar
    self.avatarMime = avatarMime
    self.avatarPath = avatarPath
    self.avatarURL = avatarURL
    self.avatarBase64 = avatarBase64
    self.avatarBytes = avatarBytes
  }

  enum CodingKeys: String, CodingKey {
    case handle
    case name
    case initials
    case hasAvatar = "has_avatar"
    case avatarMime = "avatar_mime"
    case avatarPath = "avatar_path"
    case avatarURL = "avatar_url"
    case avatarBase64 = "avatar_base64"
    case avatarBytes = "avatar_bytes"
  }
}

extension ResolvedContact {
  /// Convenience empty contact for a handle that has no Contacts entry.
  public static func unresolved(handle: String) -> ResolvedContact {
    return ResolvedContact(handle: handle)
  }

  /// Returns a copy with the given avatar URL. Typically used by the HTTP layer to decorate
  /// contacts with a reachable URL relative to the server.
  public func withAvatarURL(_ url: String?) -> ResolvedContact {
    return ResolvedContact(
      handle: handle,
      name: name,
      initials: initials,
      hasAvatar: hasAvatar,
      avatarMime: avatarMime,
      avatarPath: avatarPath,
      avatarURL: url,
      avatarBase64: avatarBase64,
      avatarBytes: avatarBytes
    )
  }

  /// Returns a copy with inline base64 avatar bytes populated (or stripped when `nil`).
  public func withAvatarBase64(_ base64: String?) -> ResolvedContact {
    return ResolvedContact(
      handle: handle,
      name: name,
      initials: initials,
      hasAvatar: hasAvatar,
      avatarMime: avatarMime,
      avatarPath: avatarPath,
      avatarURL: avatarURL,
      avatarBase64: base64,
      avatarBytes: avatarBytes
    )
  }
}

/// Status of the underlying Contacts authorization. Mirrors `CNAuthorizationStatus` without
/// requiring `Contacts` imports at call sites.
public enum ContactAuthorizationStatus: String, Sendable, Codable {
  case notDetermined = "not_determined"
  case restricted
  case denied
  case authorized
  case limited
}
