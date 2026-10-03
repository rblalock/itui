import Foundation
import SQLite
import Testing

@testable import IMsgCore

@Test
func messagesAfterPreservesRepeatedURLSendsAcrossPolls() throws {
  let db = try makeInMemoryMessageDB(includeBalloonBundleID: true)
  let now = Date()
  try db.run("INSERT INTO handle(ROWID, id) VALUES (1, '+123')")
  try db.run(
    """
    INSERT INTO message(
      ROWID, handle_id, text, guid, associated_message_guid, associated_message_type,
      balloon_bundle_id, date, is_from_me, service
    )
    VALUES (1, 1, 'https://example.com', 'msg-guid-1', NULL, 0, 'com.apple.messages.URLBalloonProvider', ?, 0, 'iMessage')
    """,
    TestDatabase.appleEpoch(now)
  )
  try db.run("INSERT INTO chat_message_join(chat_id, message_id) VALUES (1, 1)")

  let store = try MessageStore(connection: db, path: ":memory:")
  let firstPoll = try store.messagesAfter(afterRowID: 0, chatID: 1, limit: 10)
  #expect(firstPoll.map(\.rowID) == [1])

  try db.run(
    """
    INSERT INTO message(
      ROWID, handle_id, text, guid, associated_message_guid, associated_message_type,
      balloon_bundle_id, date, is_from_me, service
    )
    VALUES (2, 1, 'https://example.com', 'msg-guid-2', NULL, 0, 'com.apple.messages.URLBalloonProvider', ?, 0, 'iMessage')
    """,
    TestDatabase.appleEpoch(now.addingTimeInterval(30))
  )
  try db.run("INSERT INTO chat_message_join(chat_id, message_id) VALUES (1, 2)")

  let secondPoll = try store.messagesAfter(afterRowID: 1, chatID: 1, limit: 10)
  #expect(secondPoll.map(\.rowID) == [2])

  try db.run(
    """
    INSERT INTO message(
      ROWID, handle_id, text, guid, associated_message_guid, associated_message_type,
      balloon_bundle_id, date, is_from_me, service
    )
    VALUES (3, 1, 'https://example.com', 'msg-guid-3', NULL, 0, 'com.apple.messages.URLBalloonProvider', ?, 0, 'iMessage')
    """,
    TestDatabase.appleEpoch(now.addingTimeInterval(5 * 60))
  )
  try db.run("INSERT INTO chat_message_join(chat_id, message_id) VALUES (1, 3)")

  let thirdPoll = try store.messagesAfter(afterRowID: 1, chatID: 1, limit: 10)
  #expect(thirdPoll.map(\.rowID) == [2, 3])
  // Replaying the same rows for another client must not consume their events.
  #expect(try store.messagesAfter(afterRowID: 1, chatID: 1, limit: 10).map(\.rowID) == [2, 3])
  #expect(try store.messages(chatID: 1, limit: 10).map(\.rowID) == [3, 2, 1])
}

@Test
func messagesAfterPreservesURLSendsAcrossChats() throws {
  let db = try makeInMemoryMessageDB(includeBalloonBundleID: true)
  let now = Date()
  try db.run("INSERT INTO handle(ROWID, id) VALUES (1, '+123')")
  try db.run(
    """
    INSERT INTO message(
      ROWID, handle_id, text, guid, associated_message_guid, associated_message_type,
      balloon_bundle_id, date, is_from_me, service
    )
    VALUES (1, 1, 'https://example.com', 'msg-guid-1', NULL, 0, 'com.apple.messages.URLBalloonProvider', ?, 0, 'iMessage')
    """,
    TestDatabase.appleEpoch(now)
  )
  try db.run(
    """
    INSERT INTO message(
      ROWID, handle_id, text, guid, associated_message_guid, associated_message_type,
      balloon_bundle_id, date, is_from_me, service
    )
    VALUES (2, 1, 'https://example.com', 'msg-guid-2', NULL, 0, 'com.apple.messages.URLBalloonProvider', ?, 0, 'iMessage')
    """,
    TestDatabase.appleEpoch(now.addingTimeInterval(15))
  )
  try db.run("INSERT INTO chat_message_join(chat_id, message_id) VALUES (1, 1)")
  try db.run("INSERT INTO chat_message_join(chat_id, message_id) VALUES (2, 2)")

  let store = try MessageStore(connection: db, path: ":memory:")
  let messages = try store.messagesAfter(afterRowID: 0, chatID: nil, limit: 10)
  #expect(messages.map(\.rowID) == [1, 2])
}
