import { describe, expect, it } from "vitest"
import { buildSendBatches } from "@/features/messages/send-batches"
import {
  applyIncomingConversationMessage,
  createOptimisticConversationMessage,
} from "@/features/messages/conversation-messages"
import type { ComposerAttachment } from "@/features/messages/types"

describe("text and attachment sends", () => {
  it("reconciles text and photo as separate Messages.app echoes", () => {
    const attachment: ComposerAttachment = {
      id: "photo",
      file: new File(["photo"], "photo.jpg", { type: "image/jpeg" }),
      name: "photo.jpg",
      kind: "image",
      size: 5,
      status: "queued",
    }
    const batches = buildSendBatches("Here it is", [attachment])
    expect(batches).toHaveLength(2)
    const locals = batches.map((batch) =>
      createOptimisticConversationMessage({
        chatId: 42,
        handle: "+15555550123",
        ...batch,
      })
    )
    let messages = locals
    for (const [index, local] of locals.entries()) {
      messages = applyIncomingConversationMessage(messages, {
        chat_id: local.chat_id,
        created_at: local.created_at,
        sender: local.sender,
        is_from_me: true,
        text: local.text,
        reactions: [],
        id: index + 1,
        guid: `apple-${index}`,
        attachments: local.attachments.map((item) => ({
          ...item,
          id: index + 1,
        })),
      })
    }
    expect(messages).toHaveLength(2)
    expect(messages.some((message) => message.clientId)).toBe(false)
  })
})
