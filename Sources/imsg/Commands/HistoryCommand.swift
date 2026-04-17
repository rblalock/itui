import Commander
import Foundation
import IMsgCore

enum HistoryCommand {
  static let spec = CommandSpec(
    name: "history",
    abstract: "Show recent messages for a chat",
    discussion: nil,
    signature: CommandSignatures.withRuntimeFlags(
      CommandSignature(
        options: CommandSignatures.baseOptions() + [
          .make(label: "chatID", names: [.long("chat-id")], help: "chat rowid from 'imsg chats'"),
          .make(label: "limit", names: [.long("limit")], help: "Number of messages to show"),
          .make(
            label: "participants", names: [.long("participants")],
            help: "filter by participant handles", parsing: .upToNextOption),
          .make(label: "start", names: [.long("start")], help: "ISO8601 start (inclusive)"),
          .make(label: "end", names: [.long("end")], help: "ISO8601 end (exclusive)"),
        ],
        flags: [
          .make(
            label: "attachments", names: [.long("attachments")], help: "include attachment metadata"
          )
        ] + CommandSignatures.contactFlags()
      )
    ),
    usageExamples: [
      "imsg history --chat-id 1 --limit 10 --attachments",
      "imsg history --chat-id 1 --start 2025-01-01T00:00:00Z --json",
      "imsg history --chat-id 1 --contacts --json",
    ]
  ) { values, runtime in
    try await HistoryCommand.run(values: values, runtime: runtime)
  }

  /// Body extracted from the CommandSpec closure. See `ChatsCommand.run` for why.
  static func run(values: ParsedValues, runtime: RuntimeOptions) async throws {
    guard let chatID = values.optionInt64("chatID") else {
      throw ParsedValuesError.missingOption("chat-id")
    }
    let dbPath = values.option("db") ?? MessageStore.defaultPath
    let limit = values.optionInt("limit") ?? 50
    let showAttachments = values.flag("attachments")
    let resolveContacts = values.flag("contacts")
    let inlineAvatars = values.flag("inlineAvatars")
    let participants = values.optionValues("participants")
      .flatMap { $0.split(separator: ",").map { String($0) } }
      .filter { !$0.isEmpty }
    let filter = try MessageFilter.fromISO(
      participants: participants,
      startISO: values.option("start"),
      endISO: values.option("end")
    )

    let store = try MessageStore(path: dbPath)
    let filtered = try store.messages(chatID: chatID, limit: limit, filter: filter)

    let resolver: ContactResolver?
    if resolveContacts {
      let r = ContactResolver()
      await r.loadIfNeeded()
      resolver = r
    } else {
      resolver = nil
    }
    let delivery: ContactResolver.AvatarDelivery = inlineAvatars ? .inline : .filePath

    if runtime.jsonOutput {
      for message in filtered {
        let attachments = try store.attachments(for: message.rowID)
        let reactions = try store.reactions(for: message.rowID)
        let senderContact: ResolvedContact?
        if let resolver, !message.sender.isEmpty {
          senderContact = await resolver.resolve(message.sender, delivery: delivery)
        } else {
          senderContact = nil
        }
        let payload = MessagePayload(
          message: message,
          attachments: attachments,
          reactions: reactions,
          senderContact: senderContact
        )
        try StdoutWriter.writeJSONLine(payload)
      }
      return
    }

    for message in filtered {
      let direction = message.isFromMe ? "sent" : "recv"
      let timestamp = CLIISO8601.format(message.date)
      let senderLabel: String
      if let resolver, !message.sender.isEmpty {
        let contact = await resolver.resolve(message.sender, delivery: .metadataOnly)
        if let name = contact.name {
          senderLabel = "\(name) <\(message.sender)>"
        } else {
          senderLabel = message.sender
        }
      } else {
        senderLabel = message.sender
      }
      StdoutWriter.writeLine("\(timestamp) [\(direction)] \(senderLabel): \(message.text)")
      if message.attachmentsCount > 0 {
        if showAttachments {
          let metas = try store.attachments(for: message.rowID)
          for meta in metas {
            let name = displayName(for: meta)
            StdoutWriter.writeLine(
              "  attachment: name=\(name) mime=\(meta.mimeType) missing=\(meta.missing) path=\(meta.originalPath)"
            )
          }
        } else {
          StdoutWriter.writeLine(
            "  (\(message.attachmentsCount) attachment\(pluralSuffix(for: message.attachmentsCount)))"
          )
        }
      }
    }
  }
}
