import Foundation
import IMsgCore


struct ChatsListResponse: Codable {
  let chats: [ChatListPayload]
}

struct MessagesListResponse: Codable {
  let messages: [MessagePayload]
}

struct OkResponse: Codable {
  let ok: Bool
}

struct StagedUploadResponse: Codable {
  let upload: StagedUploadPayload
}

struct StagedUploadPayload: Codable {
  let id: String
  let filename: String
  let mimeType: String
  let totalBytes: Int64

  init(upload: UploadStager.Upload) {
    self.id = upload.id
    self.filename = upload.filename
    self.mimeType = upload.mimeType
    self.totalBytes = upload.totalBytes
  }

  enum CodingKeys: String, CodingKey {
    case id
    case filename
    case mimeType = "mime_type"
    case totalBytes = "total_bytes"
  }
}

/// Legacy response shape kept for the existing web UI. Returned only when
/// `/api/contacts?format=map` is called.
struct ContactsNameMapResponse: Codable {
  let contacts: [String: String]
}

/// New default response shape for `/api/contacts`. Includes the authorization status so
/// clients can surface an actionable error if Contacts access has not been granted yet.
struct ContactsListResponse: Codable {
  let authorization: String
  let contacts: [ResolvedContact]
  let lastUpdatedAt: String?
  let lastError: String?

  enum CodingKeys: String, CodingKey {
    case authorization, contacts
    case lastUpdatedAt = "last_updated_at"
    case lastError = "last_error"
  }
}

struct ContactResolveResponse: Codable {
  let contact: ResolvedContact
}
