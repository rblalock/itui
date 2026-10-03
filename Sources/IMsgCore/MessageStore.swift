import Foundation
import SQLite

public final class MessageStore: @unchecked Sendable {
  public static let appleEpochOffset: TimeInterval = 978_307_200

  public static var defaultPath: String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return NSString(string: home).appendingPathComponent("Library/Messages/chat.db")
  }

  public let path: String

  private let connection: Connection
  private let queue: DispatchQueue
  private let queueKey = DispatchSpecificKey<Void>()
  let hasAttributedBody: Bool
  let hasReactionColumns: Bool
  let hasThreadOriginatorGUIDColumn: Bool
  let hasDestinationCallerID: Bool
  let hasAudioMessageColumn: Bool
  let hasAttachmentUserInfo: Bool
  let hasBalloonBundleIDColumn: Bool

  public init(path: String = MessageStore.defaultPath) throws {
    let normalized = NSString(string: path).expandingTildeInPath
    self.path = normalized
    self.queue = DispatchQueue(label: "imsg.db", qos: .userInitiated)
    self.queue.setSpecific(key: queueKey, value: ())
    do {
      let uri = URL(fileURLWithPath: normalized).absoluteString
      let location = Connection.Location.uri(uri, parameters: [.mode(.readOnly)])
      self.connection = try Connection(location, readonly: true)
      self.connection.busyTimeout = 5
      let messageColumns = MessageStore.tableColumns(connection: self.connection, table: "message")
      let attachmentColumns = MessageStore.tableColumns(
        connection: self.connection,
        table: "attachment"
      )
      self.hasAttributedBody = messageColumns.contains("attributedbody")
      self.hasReactionColumns = MessageStore.reactionColumnsPresent(in: messageColumns)
      self.hasThreadOriginatorGUIDColumn = messageColumns.contains("thread_originator_guid")
      self.hasDestinationCallerID = messageColumns.contains("destination_caller_id")
      self.hasAudioMessageColumn = messageColumns.contains("is_audio_message")
      self.hasAttachmentUserInfo = attachmentColumns.contains("user_info")
      self.hasBalloonBundleIDColumn = messageColumns.contains("balloon_bundle_id")
    } catch {
      throw MessageStore.enhance(error: error, path: normalized)
    }
  }

  init(
    connection: Connection,
    path: String,
    hasAttributedBody: Bool? = nil,
    hasReactionColumns: Bool? = nil,
    hasThreadOriginatorGUIDColumn: Bool? = nil,
    hasDestinationCallerID: Bool? = nil,
    hasAudioMessageColumn: Bool? = nil,
    hasAttachmentUserInfo: Bool? = nil,
    hasBalloonBundleIDColumn: Bool? = nil
  ) throws {
    self.path = path
    self.queue = DispatchQueue(label: "imsg.db.test", qos: .userInitiated)
    self.queue.setSpecific(key: queueKey, value: ())
    self.connection = connection
    self.connection.busyTimeout = 5
    let messageColumns = MessageStore.tableColumns(connection: connection, table: "message")
    let attachmentColumns = MessageStore.tableColumns(connection: connection, table: "attachment")
    if let hasAttributedBody {
      self.hasAttributedBody = hasAttributedBody
    } else {
      self.hasAttributedBody = messageColumns.contains("attributedbody")
    }
    if let hasReactionColumns {
      self.hasReactionColumns = hasReactionColumns
    } else {
      self.hasReactionColumns = MessageStore.reactionColumnsPresent(in: messageColumns)
    }
    if let hasThreadOriginatorGUIDColumn {
      self.hasThreadOriginatorGUIDColumn = hasThreadOriginatorGUIDColumn
    } else {
      self.hasThreadOriginatorGUIDColumn = messageColumns.contains("thread_originator_guid")
    }
    if let hasDestinationCallerID {
      self.hasDestinationCallerID = hasDestinationCallerID
    } else {
      self.hasDestinationCallerID = messageColumns.contains("destination_caller_id")
    }
    if let hasAudioMessageColumn {
      self.hasAudioMessageColumn = hasAudioMessageColumn
    } else {
      self.hasAudioMessageColumn = messageColumns.contains("is_audio_message")
    }
    if let hasAttachmentUserInfo {
      self.hasAttachmentUserInfo = hasAttachmentUserInfo
    } else {
      self.hasAttachmentUserInfo = attachmentColumns.contains("user_info")
    }
    if let hasBalloonBundleIDColumn {
      self.hasBalloonBundleIDColumn = hasBalloonBundleIDColumn
    } else {
      self.hasBalloonBundleIDColumn = messageColumns.contains("balloon_bundle_id")
    }
  }

  public func listChats(limit: Int) throws -> [Chat] {
    let bodyColumn = hasAttributedBody ? "m.attributedBody" : "NULL"
    let associatedTypeColumn = hasReactionColumns ? "m.associated_message_type" : "NULL"
    let audioMessageColumn = hasAudioMessageColumn ? "m.is_audio_message" : "0"
    let sql = """
      WITH ranked_messages AS (
        SELECT
          cmj.chat_id AS chat_id,
          m.ROWID AS message_id,
          IFNULL(m.text, '') AS text,
          m.is_from_me,
          m.date,
          \(associatedTypeColumn) AS associated_type,
          \(bodyColumn) AS body,
          \(audioMessageColumn) AS is_audio_message,
          (
            SELECT COUNT(*)
            FROM message_attachment_join maj
            WHERE maj.message_id = m.ROWID
          ) AS attachment_count,
          (
            SELECT IFNULL(a.transfer_name, '')
            FROM message_attachment_join maj
            JOIN attachment a ON a.ROWID = maj.attachment_id
            WHERE maj.message_id = m.ROWID
            ORDER BY a.ROWID ASC
            LIMIT 1
          ) AS attachment_transfer_name,
          (
            SELECT IFNULL(a.mime_type, '')
            FROM message_attachment_join maj
            JOIN attachment a ON a.ROWID = maj.attachment_id
            WHERE maj.message_id = m.ROWID
            ORDER BY a.ROWID ASC
            LIMIT 1
          ) AS attachment_mime_type,
          ROW_NUMBER() OVER (
            PARTITION BY cmj.chat_id
            ORDER BY m.date DESC, m.ROWID DESC
          ) AS message_rank
        FROM chat_message_join cmj
        JOIN message m ON m.ROWID = cmj.message_id
      )
      SELECT
        c.ROWID,
        IFNULL(c.display_name, c.chat_identifier) AS name,
        c.chat_identifier,
        c.service_name,
        ranked_messages.date AS last_date,
        ranked_messages.message_id,
        ranked_messages.text,
        ranked_messages.is_from_me,
        ranked_messages.associated_type,
        ranked_messages.attachment_count,
        ranked_messages.attachment_transfer_name,
        ranked_messages.attachment_mime_type,
        ranked_messages.body,
        ranked_messages.is_audio_message
      FROM chat c
      JOIN ranked_messages
        ON ranked_messages.chat_id = c.ROWID
        AND ranked_messages.message_rank = 1
      ORDER BY ranked_messages.date DESC, ranked_messages.message_id DESC
      LIMIT ?
      """
    return try withConnection { db in
      var chats: [Chat] = []
      for row in try db.prepare(sql, limit) {
        let id = int64Value(row[0]) ?? 0
        let name = stringValue(row[1])
        let identifier = stringValue(row[2])
        let service = stringValue(row[3])
        let lastDate = appleDate(from: int64Value(row[4]))
        let messageID = int64Value(row[5]) ?? 0
        let text = stringValue(row[6])
        let isFromMe = boolValue(row[7])
        let associatedType = intValue(row[8])
        let attachmentCount = intValue(row[9]) ?? 0
        let attachmentTransferName = stringValue(row[10])
        let attachmentMimeType = stringValue(row[11])
        let body = dataValue(row[12])
        let isAudioMessage = boolValue(row[13])
        var resolvedText = text.isEmpty ? TypedStreamParser.parseAttributedBody(body) : text
        if isAudioMessage,
          let transcription = try audioTranscription(for: messageID),
          !transcription.isEmpty
        {
          resolvedText = transcription
        }

        chats.append(
          Chat(
            id: id,
            identifier: identifier,
            name: name,
            service: service,
            lastMessageAt: lastDate,
            preview: MessageStore.chatPreviewSummary(
              text: resolvedText,
              isFromMe: isFromMe,
              associatedType: associatedType,
              attachmentCount: attachmentCount,
              attachmentTransferName: attachmentTransferName,
              attachmentMimeType: attachmentMimeType
            )
          )
        )
      }
      return chats
    }
  }

  public func chatInfo(chatID: Int64) throws -> ChatInfo? {
    let sql = """
      SELECT c.ROWID, IFNULL(c.chat_identifier, '') AS identifier, IFNULL(c.guid, '') AS guid,
             IFNULL(c.display_name, c.chat_identifier) AS name, IFNULL(c.service_name, '') AS service
      FROM chat c
      WHERE c.ROWID = ?
      LIMIT 1
      """
    return try withConnection { db in
      for row in try db.prepare(sql, chatID) {
        let id = int64Value(row[0]) ?? 0
        let identifier = stringValue(row[1])
        let guid = stringValue(row[2])
        let name = stringValue(row[3])
        let service = stringValue(row[4])
        return ChatInfo(
          id: id,
          identifier: identifier,
          guid: guid,
          name: name,
          service: service
        )
      }
      return nil
    }
  }

  public func participants(chatID: Int64) throws -> [String] {
    let sql = """
      SELECT h.id
      FROM chat_handle_join chj
      JOIN handle h ON h.ROWID = chj.handle_id
      WHERE chj.chat_id = ?
      ORDER BY h.id ASC
      """
    return try withConnection { db in
      var results: [String] = []
      var seen = Set<String>()
      for row in try db.prepare(sql, chatID) {
        let handle = stringValue(row[0])
        if handle.isEmpty { continue }
        if seen.insert(handle).inserted {
          results.append(handle)
        }
      }
      return results
    }
  }

  func withConnection<T>(_ block: (Connection) throws -> T) throws -> T {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      return try block(connection)
    }
    return try queue.sync {
      try block(connection)
    }
  }

  private static func chatPreviewSummary(
    text: String,
    isFromMe: Bool,
    associatedType: Int?,
    attachmentCount: Int,
    attachmentTransferName: String,
    attachmentMimeType: String
  ) -> String {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

    let summary: String
    if let associatedType, ReactionType.isReaction(associatedType) {
      summary = reactionPreviewSummary(text: text, associatedType: associatedType)
    } else if !trimmedText.isEmpty {
      summary = trimmedText
    } else if attachmentCount > 0 {
      summary = attachmentPreviewSummary(
        count: attachmentCount,
        transferName: attachmentTransferName,
        mimeType: attachmentMimeType
      )
    } else {
      summary = "Message"
    }

    return isFromMe ? "You: \(summary)" : summary
  }

  private static func reactionPreviewSummary(text: String, associatedType: Int) -> String {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let customEmoji = trimmedText.isEmpty ? nil : trimmedText

    let reactionType: ReactionType?
    if ReactionType.isReactionRemove(associatedType) {
      reactionType = ReactionType.fromRemoval(associatedType, customEmoji: customEmoji)
    } else {
      reactionType = ReactionType(rawValue: associatedType, customEmoji: customEmoji)
    }

    let emoji = reactionType?.emoji ?? customEmoji ?? ""
    if ReactionType.isReactionRemove(associatedType) {
      return emoji.isEmpty ? "Removed a reaction" : "Removed \(emoji)"
    }

    return emoji.isEmpty ? "Reacted to a message" : "Reacted with \(emoji)"
  }

  private static func attachmentPreviewSummary(
    count: Int,
    transferName: String,
    mimeType: String
  ) -> String {
    if count > 1 {
      return "\(count) attachments"
    }

    let trimmedTransferName = transferName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedTransferName.isEmpty {
      return trimmedTransferName
    }

    if mimeType.hasPrefix("image/") {
      return "Photo"
    }
    if mimeType.hasPrefix("video/") {
      return "Video"
    }
    if mimeType.hasPrefix("audio/") {
      return "Audio message"
    }

    return "Attachment"
  }
}
