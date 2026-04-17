import Commander
import Foundation
import IMsgCore

/// List or resolve contacts from the local Contacts database. The JSON shape matches the
/// `/api/contacts` HTTP response so the CLI can be used as a drop-in replacement when
/// scripting.
enum ContactsCommand {
  static let spec = CommandSpec(
    name: "contacts",
    abstract: "List resolved contacts (names + avatar paths)",
    discussion: """
      Reads the local Contacts database via the Contacts framework. A one-time prompt may
      appear the first time you run this command; deny and the command will emit only the
      handles you pass in.
      """,
    signature: CommandSignatures.withRuntimeFlags(
      CommandSignature(
        options: [
          .make(
            label: "handle",
            names: [.long("handle")],
            help: "resolve a single handle (phone/email) instead of listing all contacts"
          )
        ],
        flags: [
          .make(
            label: "inlineAvatars",
            names: [.long("inline-avatars")],
            help: "include avatar bytes as base64 in JSON output"
          )
        ]
      )
    ),
    usageExamples: [
      "imsg contacts --json",
      "imsg contacts --handle +15551234567 --json",
      "imsg contacts --handle +15551234567 --inline-avatars --json",
    ]
  ) { values, runtime in
    try await ContactsCommand.run(values: values, runtime: runtime)
  }

  /// Body extracted out of the CommandSpec closure. See `ChatsCommand.run` for why.
  static func run(values: ParsedValues, runtime: RuntimeOptions) async throws {
    let inlineAvatars = values.flag("inlineAvatars")
    let delivery: ContactResolver.AvatarDelivery = inlineAvatars ? .inline : .filePath

    let resolver = ContactResolver()
    await resolver.loadIfNeeded()

    if let handle = values.option("handle"), !handle.isEmpty {
      let contact = await resolver.resolve(handle, delivery: delivery)
      if runtime.jsonOutput {
        try StdoutWriter.writeJSONLine(contact)
      } else {
        renderContact(contact)
      }
      return
    }

    let contacts = await resolver.allContacts(delivery: delivery)
    if runtime.jsonOutput {
      let status = await resolver.authorizationStatus()
      try StdoutWriter.writeJSONLine(
        ContactsCommandListPayload(authorization: status.rawValue, contacts: contacts))
      return
    }

    let status = await resolver.authorizationStatus()
    StdoutWriter.writeLine("authorization=\(status.rawValue) count=\(contacts.count)")
    for contact in contacts {
      renderContact(contact)
    }
  }

  private static func renderContact(_ contact: ResolvedContact) {
    let name = contact.name ?? "(unknown)"
    var suffix = ""
    if contact.hasAvatar, let path = contact.avatarPath {
      suffix = " avatar=\(path)"
    } else if contact.hasAvatar {
      suffix = " avatar=(cached in memory)"
    }
    StdoutWriter.writeLine("\(contact.handle) — \(name) [\(contact.initials)]\(suffix)")
  }
}

/// Wire-format analog of the HTTP `/api/contacts` response, reused so CLI consumers can
/// parse the same structure.
struct ContactsCommandListPayload: Codable {
  let authorization: String
  let contacts: [ResolvedContact]
}
