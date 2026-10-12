import Foundation
import Testing

@testable import IMsgCore

@Test
func messageGUIDLookupFindsOlderParentsAndStaysInTheRequestedChat() throws {
  let store = try TestDatabase.makeStore(includeReactionColumns: true)
  try store.withConnection { db in
    try db.run("UPDATE message SET guid = 'parent-guid' WHERE ROWID = 1")
    try db.run("INSERT INTO chat_message_join(chat_id, message_id) VALUES (2, 2)")
    try db.run("UPDATE message SET guid = 'other-chat-guid' WHERE ROWID = 2")
    try db.run("DELETE FROM chat_message_join WHERE chat_id = 1 AND message_id = 2")
  }
  let parent = try store.messages(
    chatID: 1, limit: 1, filter: MessageFilter(guids: ["PARENT-GUID"]))
  #expect(parent.map(\.rowID) == [1])
  let other = try store.messages(
    chatID: 1, limit: 10, filter: MessageFilter(guids: ["other-chat-guid"]))
  #expect(other.isEmpty)
  let injection = try store.messages(
    chatID: 1, limit: 10, filter: MessageFilter(guids: ["' OR 1=1 --"]))
  #expect(injection.isEmpty)
}

@Test
func messageGUIDLookupOnOlderSchemaReturnsNoMatch() throws {
  let store = try TestDatabase.makeStore()
  #expect(
    try store.messages(chatID: 1, limit: 10, filter: MessageFilter(guids: ["missing"])).isEmpty)
  #expect(try store.messages(chatID: 1, limit: 10).count == 3)
}
