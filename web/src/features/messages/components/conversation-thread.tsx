import { Badge } from "@/components/ui/badge"
import { Spinner } from "@/components/ui/spinner"
import { MessageCircleIcon } from "lucide-react"
import { useEffect, useState, type RefObject } from "react"

import { MessageContent } from "@/features/messages/components/message-content"
import { MessageReplyPreview } from "@/features/messages/components/message-reply-preview"
import { useReplyContext } from "@/features/messages/hooks/use-reply-context"
import {
  normalizeMessageGuid,
  replyParentGuid,
} from "@/features/messages/reply-context"
import { ThreadAvatar } from "@/features/messages/components/thread-avatar"
import { senderDisplayName } from "@/features/messages/thread-identity"
import type {
  ActiveConversation,
  ConversationMessage,
} from "@/features/messages/types"
import {
  formatDayDivider,
  formatMessageTime,
  sameBubbleGroup,
  toDate,
} from "@/features/messages/utils"
import { cn } from "@/lib/utils"

const incomingAvatarContacts = (
  activeConversation: ActiveConversation,
  message: ConversationMessage
) => {
  if (activeConversation.kind === "thread" && activeConversation.isGroup) {
    return message.sender_contact ? [message.sender_contact] : []
  }

  return activeConversation.avatarContacts
}

export function ConversationThread({
  activeConversation,
  isLoadingChats,
  isLoadingSelectedMessages,
  loadError,
  onRetryMessage,
  scrollRef,
  selectedMessages,
}: {
  activeConversation: ActiveConversation | null
  isLoadingChats: boolean
  isLoadingSelectedMessages: boolean
  loadError?: string | null
  onRetryMessage: (message: ConversationMessage) => void | Promise<void>
  scrollRef: RefObject<HTMLDivElement | null>
  selectedMessages: ConversationMessage[]
}) {
  const chatId =
    activeConversation?.kind === "thread" ? activeConversation.id : null
  const replies = useReplyContext(selectedMessages, chatId)
  const [highlighted, setHighlighted] = useState<string | null>(null)
  useEffect(() => {
    if (!highlighted) return
    const timer = window.setTimeout(() => setHighlighted(null), 1800)
    return () => window.clearTimeout(timer)
  }, [highlighted])
  const jumpToMessage = (guid: string) => {
    const target = [
      ...(scrollRef.current?.querySelectorAll<HTMLElement>(
        "[data-message-guid]"
      ) ?? []),
    ].find((element) => element.dataset.messageGuid === guid)
    if (!target) return
    target.scrollIntoView({
      block: "center",
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "auto"
        : "smooth",
    })
    target.focus({ preventScroll: true })
    setHighlighted(guid)
  }
  return (
    <div
      className="min-h-0 flex-1 overflow-x-hidden overflow-y-auto overscroll-contain bg-background"
      ref={scrollRef}
    >
      {!activeConversation ? (
        <div className="mx-auto flex h-full max-w-md flex-col items-center justify-center gap-3 px-6 text-center">
          {isLoadingChats ? (
            <>
              <Spinner className="size-5 text-muted-foreground" />
              <p className="text-sm text-muted-foreground">
                Loading conversations
              </p>
            </>
          ) : loadError ? (
            <>
              <div className="flex size-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
                <MessageCircleIcon />
              </div>
              <div className="flex flex-col gap-1">
                <h3 className="text-sm font-medium">Can’t load messages</h3>
                <p className="text-sm text-muted-foreground">{loadError}</p>
              </div>
            </>
          ) : (
            <>
              <div className="flex size-12 items-center justify-center rounded-full bg-secondary text-muted-foreground">
                <MessageCircleIcon />
              </div>
              <div className="flex flex-col gap-1">
                <h3 className="text-sm font-medium">No conversations yet</h3>
                <p className="text-sm text-muted-foreground">
                  This account doesn’t have any chats to display yet.
                </p>
              </div>
            </>
          )}
        </div>
      ) : isLoadingSelectedMessages ? (
        <div className="mx-auto flex h-full max-w-md flex-col items-center justify-center gap-3 px-6 text-center">
          <Spinner className="size-5 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">Loading conversation</p>
        </div>
      ) : loadError && selectedMessages.length === 0 ? (
        <div className="mx-auto flex h-full max-w-md flex-col items-center justify-center gap-3 px-6 text-center">
          <div className="flex size-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
            <MessageCircleIcon />
          </div>
          <div className="flex flex-col gap-1">
            <h3 className="text-sm font-medium">
              Can’t load this conversation
            </h3>
            <p className="text-sm text-muted-foreground">{loadError}</p>
          </div>
        </div>
      ) : selectedMessages.length === 0 ? (
        <div className="mx-auto flex h-full max-w-md flex-col items-center justify-center gap-3 px-6 text-center">
          <ThreadAvatar
            contacts={activeConversation.avatarContacts}
            overflowCount={activeConversation.avatarOverflowCount}
            size="lg"
            title={activeConversation.title}
          />
          <div className="flex flex-col gap-1">
            <h3 className="text-sm font-medium">
              {activeConversation.kind === "draft"
                ? "Ready to start"
                : "No messages yet"}
            </h3>
            <p className="text-sm text-muted-foreground">
              {activeConversation.kind === "draft"
                ? "Send the first message below to create this conversation."
                : "Start the conversation below."}
            </p>
          </div>
        </div>
      ) : (
        <div className="mx-auto flex w-full max-w-3xl flex-col gap-3 px-3 py-5 sm:gap-3.5 sm:px-6 sm:py-6">
          {selectedMessages.map((message, index) => {
            const guid = normalizeMessageGuid(message.guid)
            const parentGuid = replyParentGuid(message)
            const replyPreview = parentGuid ? (
              <MessageReplyPreview
                parent={replies.parents.get(parentGuid)}
                onJump={
                  replies.loaded.has(parentGuid)
                    ? () => jumpToMessage(parentGuid)
                    : undefined
                }
                onRetry={() => replies.retry(parentGuid)}
              />
            ) : null
            const previousMessage = selectedMessages[index - 1]
            const nextMessage = selectedMessages[index + 1]
            const showDayDivider =
              !previousMessage ||
              toDate(previousMessage.created_at).toDateString() !==
                toDate(message.created_at).toDateString()
            const showAvatar =
              !message.is_from_me && !sameBubbleGroup(message, previousMessage)
            const showTimestamp = !sameBubbleGroup(message, nextMessage)
            const showSenderLabel =
              !message.is_from_me &&
              showAvatar &&
              activeConversation.kind === "thread" &&
              activeConversation.isGroup

            return (
              <div
                className={cn(
                  "flex flex-col gap-1.5 rounded-xl outline-none",
                  highlighted === guid &&
                    "ring-2 ring-primary ring-offset-4 ring-offset-background"
                )}
                data-message-guid={guid}
                tabIndex={-1}
                key={message.clientId ?? message.guid ?? String(message.id)}
              >
                {showDayDivider ? (
                  <div className="sticky top-3 z-10 flex justify-center py-2">
                    <Badge
                      className="text-app-day-divider border-border/70 bg-background/92 px-2.5 tracking-[0.18em] uppercase shadow-sm backdrop-blur-sm"
                      variant="outline"
                    >
                      {formatDayDivider(message.created_at)}
                    </Badge>
                  </div>
                ) : null}

                <div
                  className={cn(
                    "flex gap-2",
                    message.is_from_me ? "justify-end" : "justify-start"
                  )}
                >
                  {message.is_from_me ? (
                    <div className="flex max-w-[min(84vw,24rem)] flex-col items-end gap-1 sm:max-w-[72%]">
                      <MessageContent
                        message={message}
                        replyPreview={replyPreview}
                        onRetryMessage={onRetryMessage}
                        service={activeConversation.service}
                      />

                      {showTimestamp ? (
                        <span className="text-app-meta px-1 text-muted-foreground">
                          {formatMessageTime(message.created_at)}
                        </span>
                      ) : null}
                    </div>
                  ) : (
                    <div className="flex max-w-[min(84vw,24rem)] flex-col gap-1 sm:max-w-[72%]">
                      <div className="flex items-start gap-2 sm:gap-2.5">
                        {showAvatar ? (
                          <ThreadAvatar
                            contacts={incomingAvatarContacts(
                              activeConversation,
                              message
                            )}
                            size="sm"
                            title={senderDisplayName(message)}
                          />
                        ) : (
                          <div className="size-6 shrink-0" />
                        )}

                        <div className="min-w-0 flex-1">
                          {showSenderLabel ? (
                            <p className="text-app-meta pb-1 font-medium tracking-[0.08em] text-muted-foreground uppercase">
                              {senderDisplayName(message)}
                            </p>
                          ) : null}

                          <MessageContent
                            message={message}
                            replyPreview={replyPreview}
                            onRetryMessage={onRetryMessage}
                            service={activeConversation.service}
                          />
                        </div>
                      </div>

                      {showTimestamp ? (
                        <span className="text-app-meta pl-[2.125rem] text-muted-foreground">
                          {formatMessageTime(message.created_at)}
                        </span>
                      ) : null}
                    </div>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
