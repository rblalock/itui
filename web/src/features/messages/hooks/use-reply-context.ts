import { useEffect, useMemo, useState } from "react"
import type { Message } from "@/lib/imsg"
import { MessagesService } from "@/features/messages/services/messages-service"
import {
  indexMessagesByGuid,
  replyParentGuid,
} from "@/features/messages/reply-context"

export function useReplyContext(messages: Message[], chatId: number | null) {
  const service = useMemo(() => new MessagesService(), [])
  const [cache, setCache] = useState<{
    chatId: number | null
    parents: Map<string, Message | null>
  }>({ chatId: null, parents: new Map() })
  const loaded = useMemo(
    () => indexMessagesByGuid(messages, chatId),
    [messages, chatId]
  )
  const remote =
    cache.chatId === chatId ? cache.parents : new Map<string, Message | null>()
  const needed = [
    ...new Set(
      messages.map(replyParentGuid).filter((guid): guid is string => !!guid)
    ),
  ]
    .filter((guid) => !loaded.has(guid) && !remote.has(guid))
    .sort()
    .join(",")

  useEffect(() => {
    if (chatId == null || !needed) return
    let cancelled = false
    const guids = needed.split(",")
    const save = (found: Message[]) => {
      if (cancelled) return
      const indexed = indexMessagesByGuid(found, chatId)
      const parents = new Map(
        guids.map((guid) => [guid, indexed.get(guid) ?? null])
      )
      setCache((current) => ({
        chatId,
        parents: new Map([
          ...(current.chatId === chatId ? current.parents : new Map()),
          ...parents,
        ]),
      }))
    }
    void service
      .listMessagesByGuids(chatId, guids)
      .then(save)
      .catch(() => save([]))
    return () => {
      cancelled = true
    }
  }, [chatId, needed, service])

  return {
    loaded,
    parents: new Map([...remote, ...loaded]),
    retry: (guid: string) =>
      setCache((current) => {
        if (current.chatId !== chatId) return current
        const parents = new Map(current.parents)
        parents.delete(guid)
        return { ...current, parents }
      }),
  }
}
