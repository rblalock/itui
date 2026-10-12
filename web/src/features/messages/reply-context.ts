import type { Message } from "@/lib/imsg"

export const normalizeMessageGuid = (guid: string) =>
  guid.trim().split("/").at(-1)?.toLowerCase() ?? ""

export function replyParentGuid(message: Message): string | null {
  if (message.is_reaction) return null
  for (const value of [message.reply_to_guid, message.thread_originator_guid]) {
    const guid = value ? normalizeMessageGuid(value) : ""
    if (guid && guid !== normalizeMessageGuid(message.guid)) return guid
  }
  return null
}

export function indexMessagesByGuid(
  messages: Message[],
  chatId: number | null
) {
  const result = new Map<string, Message>()
  for (const message of messages) {
    if (message.chat_id !== chatId || !message.guid) continue
    result.set(normalizeMessageGuid(message.guid), message)
  }
  return result
}
