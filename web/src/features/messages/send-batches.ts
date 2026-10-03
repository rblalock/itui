import type { ComposerAttachment } from "@/features/messages/types"

// Messages.app sends text and each attachment as separate messages. Mirror that
// shape locally so every optimistic bubble can reconcile with one database row.
export function buildSendBatches(
  text: string,
  attachments: ComposerAttachment[]
) {
  const batches: { text: string; attachments: ComposerAttachment[] }[] = []
  if (text.trim()) batches.push({ text, attachments: [] })
  batches.push(
    ...attachments.map((attachment) => ({
      text: "",
      attachments: [attachment],
    }))
  )
  return batches
}
