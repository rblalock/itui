import { describe, expect, it } from "vitest"
import type { Message } from "@/lib/imsg"
import {
  indexMessagesByGuid,
  replyParentGuid,
} from "@/features/messages/reply-context"

const message = (values: Partial<Message> = {}): Message => ({
  id: 1,
  chat_id: 2,
  guid: "message-1",
  sender: "+15555550123",
  created_at: "2026-10-12T12:00:00Z",
  is_from_me: false,
  text: "Hello",
  attachments: [],
  reactions: [],
  ...values,
})

describe("reply context", () => {
  it("prefers a direct reply target over the thread root", () => {
    expect(
      replyParentGuid(
        message({ reply_to_guid: "p:0/PARENT", thread_originator_guid: "root" })
      )
    ).toBe("parent")
  })
  it("uses native thread roots and ignores self references", () => {
    expect(replyParentGuid(message({ thread_originator_guid: "ROOT" }))).toBe(
      "root"
    )
    expect(
      replyParentGuid(message({ thread_originator_guid: "MESSAGE-1" }))
    ).toBeNull()
    expect(replyParentGuid(message())).toBeNull()
  })
  it("does not present tapbacks as threaded replies", () => {
    expect(
      replyParentGuid(message({ is_reaction: true, reply_to_guid: "parent" }))
    ).toBeNull()
  })
  it("indexes only messages in the active conversation", () => {
    const parent = message({ guid: "PARENT" })
    expect(
      indexMessagesByGuid([parent, message({ chat_id: 3, guid: "other" })], 2)
    ).toEqual(new Map([["parent", parent]]))
    expect(indexMessagesByGuid([parent], null)).toEqual(new Map())
  })
})
