import CryptoKit
import Foundation

/// Resolves iMessage/SMS handles (phone numbers, emails) to names and avatars using the
/// local Contacts database.
///
/// `ContactResolver` is an actor so it is safe to share across HTTP handlers, WebSocket
/// streams, RPC subscriptions, and CLI commands. The first call to ``loadIfNeeded()``
/// enumerates `CNContactStore` and caches it until a change notification or expiry; subsequent lookups
/// are O(1).
///
/// Avatars are written lazily to an on-disk cache the first time a handle is resolved with
/// `includeAvatarFile = true`. Cached files are stable across runs so a web client can link
/// to them by URL or path without re-issuing work per request.
public actor ContactResolver {
  public enum AvatarDelivery: Sendable {
    /// Metadata only (`has_avatar`, `avatar_mime`). No filesystem I/O, no base64.
    case metadataOnly
    /// Include `avatar_path` by exporting the image to the on-disk cache on demand.
    case filePath
    /// Include both `avatar_path` and `avatar_base64` (full image bytes, base64-encoded).
    case inline
  }

  /// Per-contact data indexed in memory after `loadIfNeeded()` completes.
  struct ContactRecord: Sendable, Equatable {
    let canonicalKey: String
    let name: String
    let initials: String
    let thumbnailData: Data?
    let mime: String?
    let fileExtension: String?
  }

  private var records: [ContactRecord] = []
  /// All lookup keys (handle, handle.lowercased(), phone suffix digits, canonical) map to the
  /// same index in `records` so that any variant of a handle resolves to the same contact.
  private var index: [String: Int] = [:]
  struct LoadResult: Sendable {
    let authorization: ContactAuthorizationStatus
    let records: [ContactRecord]
    let error: String?
  }

  private var loaded = false
  private var lastAttempt = Date.distantPast
  private var loadTask: Task<LoadResult, Never>?
  private var loadID: UUID?
  private var observation: ContactChangeObservation?
  private let fetchContacts: @Sendable () async -> LoadResult
  public private(set) var revision = UUID().uuidString
  public private(set) var lastLoadedAt: Date?
  public private(set) var lastError: String?
  private var authorization: ContactAuthorizationStatus = .notDetermined

  /// Base directory for exported avatar images. Defaults to `~/Library/Caches/imsg/avatars`.
  public let avatarCacheDirectory: URL

  /// Optional override for HTTP avatar URL generation. When set, `ResolvedContact.avatarURL`
  /// is produced by calling `avatarURLBuilder(handle)`. Leave nil in non-HTTP contexts.
  private var avatarURLBuilder: (@Sendable (String) -> String?)?

  public init() {
    self.avatarCacheDirectory = ContactResolver.defaultAvatarCacheDirectory
    self.avatarURLBuilder = nil
    self.fetchContacts = ContactResolver.fetchAllContacts
  }

  /// Use this when the caller wants a non-default avatar cache directory (tests, custom
  /// installs, etc). Avoid default arguments so Swift 6 does not treat the defaulted value
  /// as actor-isolated at each call site.
  public init(avatarCacheDirectory: URL) {
    self.avatarCacheDirectory = avatarCacheDirectory
    self.avatarURLBuilder = nil
    self.fetchContacts = ContactResolver.fetchAllContacts
  }

  init(avatarCacheDirectory: URL, fetchContacts: @escaping @Sendable () async -> LoadResult) {
    self.avatarCacheDirectory = avatarCacheDirectory
    self.avatarURLBuilder = nil
    self.fetchContacts = fetchContacts
  }

  // MARK: - Public API

  /// Installs (or replaces) the avatar URL builder after construction. Useful when the HTTP
  /// server is configured after the resolver has been built.
  public func setAvatarURLBuilder(_ builder: (@Sendable (String) -> String?)?) {
    self.avatarURLBuilder = builder
  }

  /// Coalesces concurrent reads and refreshes at least once a minute. Failed loads
  /// retry after five seconds rather than permanently caching an empty address book.
  public func loadIfNeeded() async {
    if observation == nil {
      observation = ContactChangeObservation { [weak self] in
        Task { await self?.invalidate() }
      }
    }
    if let loadTask, let loadID {
      applyLoadedContacts(await loadTask.value, id: loadID)
      return
    }
    let lifetime: TimeInterval = loaded && lastError == nil ? 60 : 5
    guard Date().timeIntervalSince(lastAttempt) >= lifetime else { return }

    let id = UUID()
    let fetch = fetchContacts
    let task = Task { await fetch() }
    loadTask = task
    loadID = id
    lastAttempt = Date()
    applyLoadedContacts(await task.value, id: id)
  }

  public func invalidate() {
    lastAttempt = .distantPast
  }

  public func refresh() async {
    if let loadTask, let loadID {
      applyLoadedContacts(await loadTask.value, id: loadID)
    }
    invalidate()
    await loadIfNeeded()
  }

  /// Returns the authorization state of the Contacts store the last time it was probed.
  public func authorizationStatus() -> ContactAuthorizationStatus {
    return authorization
  }

  /// Resolve a single handle (phone number or email) to a `ResolvedContact`.
  ///
  /// - Parameters:
  ///   - handle: The raw handle, exactly as stored in the Messages database.
  ///   - delivery: How to deliver avatar bytes (metadata only, file path, or inline base64).
  /// - Returns: A contact with as much information as could be derived. Handles that have no
  ///   Contacts entry get an `unresolved` shell with only the handle populated, so the
  ///   caller can still render a fallback UI with initials.
  public func resolve(
    _ handle: String,
    delivery: AvatarDelivery = .filePath
  ) async -> ResolvedContact {
    await loadIfNeeded()

    guard let record = record(for: handle) else {
      return ResolvedContact.unresolved(handle: handle)
    }

    let hasAvatar = record.thumbnailData != nil
    var avatarPath: String?
    var avatarBase64: String?

    if hasAvatar {
      switch delivery {
      case .metadataOnly:
        break
      case .filePath:
        avatarPath = ensureAvatarOnDisk(for: record)
      case .inline:
        avatarPath = ensureAvatarOnDisk(for: record)
        avatarBase64 = record.thumbnailData?.base64EncodedString()
      }
    }

    let baseURL = avatarURLBuilder?(handle)
    let avatarURL = baseURL.map { "\($0)\($0.contains("?") ? "&" : "?")v=\(revision)" }
    return ResolvedContact(
      handle: handle,
      name: record.name.isEmpty ? nil : record.name,
      initials: record.initials,
      hasAvatar: hasAvatar,
      avatarMime: record.mime,
      avatarPath: avatarPath,
      avatarURL: avatarURL,
      avatarBase64: avatarBase64,
      avatarBytes: record.thumbnailData?.count ?? 0
    )
  }

  /// Batch variant. Produces a mapping from handle -> ResolvedContact for every input.
  public func resolveMany(
    _ handles: [String],
    delivery: AvatarDelivery = .filePath
  ) async -> [String: ResolvedContact] {
    var result: [String: ResolvedContact] = [:]
    result.reserveCapacity(handles.count)
    for handle in handles {
      result[handle] = await resolve(handle, delivery: delivery)
    }
    return result
  }

  /// Returns every resolvable contact in the local Contacts store.
  public func allContacts(delivery: AvatarDelivery = .filePath) async -> [ResolvedContact] {
    await loadIfNeeded()
    var contacts: [ResolvedContact] = []
    contacts.reserveCapacity(records.count)
    for record in records {
      let contact = await resolve(record.canonicalKey, delivery: delivery)
      contacts.append(contact)
    }
    return contacts
  }

  /// Legacy API used by the existing web UI: returns a handle -> display-name map. Kept
  /// stable so older clients keep working.
  public func nameMap() async -> [String: String] {
    await loadIfNeeded()
    var table: [String: String] = [:]
    for (key, idx) in index {
      let record = records[idx]
      if !record.name.isEmpty {
        table[key] = record.name
      }
    }
    return table
  }

  /// Reads the raw avatar bytes for a handle from the on-disk cache, exporting on demand if
  /// the file is not yet materialized. Used by the HTTP avatar endpoint.
  public func avatarData(for handle: String) async -> (data: Data, mime: String)? {
    await loadIfNeeded()
    guard
      let record = record(for: handle),
      let data = record.thumbnailData,
      let mime = record.mime
    else {
      return nil
    }
    _ = ensureAvatarOnDisk(for: record)
    return (data, mime)
  }

  // MARK: - Internals

  private func applyLoadedContacts(_ result: LoadResult, id: UUID) {
    guard loadID == id else { return }
    loadTask = nil
    loadID = nil
    lastError = result.error
    // Keep a valid snapshot after a transient enumeration failure. Explicitly
    // revoked access clears it so we do not serve previously permitted data.
    if result.error == nil || result.authorization == .denied || result.authorization == .restricted
    {
      let nextRecords = result.records.sorted {
        $0.canonicalKey == $1.canonicalKey ? $0.name < $1.name : $0.canonicalKey < $1.canonicalKey
      }
      if records != nextRecords || authorization != result.authorization {
        revision = UUID().uuidString
      }
      records = nextRecords
      index = ContactResolver.buildIndex(records: records)
      loaded = result.error == nil
      if loaded { lastLoadedAt = Date() }
    }
    authorization = result.authorization
  }

  private func record(for handle: String) -> ContactRecord? {
    if let idx = index[handle] { return records[idx] }
    let lower = handle.lowercased()
    if let idx = index[lower] { return records[idx] }
    let digits = handle.filter(\.isNumber)
    if digits.count >= 10 {
      let suffix = String(digits.suffix(10))
      if let idx = index[suffix] { return records[idx] }
    }
    return nil
  }

  /// Ensures the avatar for `record` is present in the cache directory. Returns the
  /// absolute path, or `nil` on any filesystem error.
  private func ensureAvatarOnDisk(for record: ContactRecord) -> String? {
    guard
      let data = record.thumbnailData,
      let ext = record.fileExtension
    else {
      return nil
    }
    let fm = FileManager.default
    do {
      if !fm.fileExists(atPath: avatarCacheDirectory.path) {
        try fm.createDirectory(
          at: avatarCacheDirectory,
          withIntermediateDirectories: true
        )
      }
    } catch {
      return nil
    }

    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let filename = "\(ContactResolver.sanitize(key: record.canonicalKey))-\(digest).\(ext)"
    let url = avatarCacheDirectory.appendingPathComponent(filename)

    if fm.fileExists(atPath: url.path) {
      // Content-addressed files cannot reuse an old image after a Contacts edit.
      return url.path
    }

    do {
      try data.write(to: url, options: .atomic)
      return url.path
    } catch {
      return nil
    }
  }

  // MARK: - Static helpers

  public static var defaultAvatarCacheDirectory: URL {
    let base: URL
    if let caches = try? FileManager.default.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ) {
      base = caches
    } else {
      base = FileManager.default.temporaryDirectory
    }
    return base.appendingPathComponent("imsg/avatars", isDirectory: true)
  }

  static func sanitize(key: String) -> String {
    let allowed: Set<Character> = Set(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+._-@")
    var out = ""
    out.reserveCapacity(key.count)
    for ch in key {
      if allowed.contains(ch) {
        out.append(ch)
      } else {
        out.append("_")
      }
    }
    // Avoid empty filenames.
    return out.isEmpty ? "unknown" : out
  }

  static func computeInitials(given: String, family: String, organization: String) -> String {
    func firstLetter(_ s: String) -> Character? {
      for ch in s where ch.isLetter {
        return Character(ch.uppercased())
      }
      return nil
    }
    var out = ""
    if let g = firstLetter(given) { out.append(g) }
    if let f = firstLetter(family) { out.append(f) }
    if out.isEmpty, let o = firstLetter(organization) { out.append(o) }
    return out
  }

  static func detectMime(from data: Data) -> (mime: String, ext: String)? {
    guard data.count >= 4 else { return nil }
    let bytes = [UInt8](data.prefix(12))
    if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
      return ("image/jpeg", "jpg")
    }
    if bytes.count >= 8,
      bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
      bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A
    {
      return ("image/png", "png")
    }
    if bytes.count >= 12,
      bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70
    {
      // ISO BMFF container. Common brands: heic, heix, mif1, msf1.
      let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
      switch brand {
      case "heic", "heix", "hevc", "hevx":
        return ("image/heic", "heic")
      case "mif1", "msf1":
        return ("image/heif", "heif")
      default:
        return ("application/octet-stream", "bin")
      }
    }
    if bytes.count >= 6,
      bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38
    {
      return ("image/gif", "gif")
    }
    return ("application/octet-stream", "bin")
  }

  private static func buildIndex(records: [ContactRecord]) -> [String: Int] {
    var index: [String: Int] = [:]
    for (idx, record) in records.enumerated() {
      let canonical = record.canonicalKey
      if canonical.isEmpty { continue }
      // Map the canonical key, its lowercased form (for emails with mixed case), and the
      // last-10-digits form (to forgive extensions/country prefixes) all to the same record.
      index[canonical] = idx
      let lower = canonical.lowercased()
      if lower != canonical { index[lower] = idx }
      let digits = canonical.filter(\.isNumber)
      if digits.count >= 10 {
        let suffix = String(digits.suffix(10))
        if index[suffix] == nil {
          index[suffix] = idx
        }
      }
    }
    return index
  }
}
