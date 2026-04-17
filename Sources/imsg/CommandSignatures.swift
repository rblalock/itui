import Commander
import IMsgCore

enum CommandSignatures {
  static func baseOptions() -> [OptionDefinition] {
    [
      .make(
        label: "db",
        names: [.long("db")],
        help: "Path to chat.db (defaults to ~/Library/Messages/chat.db)"
      )
    ]
  }

  /// Shared `--contacts` / `--inline-avatars` flags used by `chats`, `history`, `watch`,
  /// and `contacts`. Kept in one place so every command speaks the same dialect.
  static func contactFlags() -> [FlagDefinition] {
    [
      .make(
        label: "contacts",
        names: [.long("contacts")],
        help: "resolve handles to Contacts (name + avatar path)"
      ),
      .make(
        label: "inlineAvatars",
        names: [.long("inline-avatars")],
        help: "when --contacts is set, also embed avatar bytes as base64"
      ),
    ]
  }

  static func withRuntimeFlags(_ signature: CommandSignature) -> CommandSignature {
    signature.withStandardRuntimeFlags()
  }
}
