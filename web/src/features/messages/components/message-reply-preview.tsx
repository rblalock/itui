import type { Message } from "@/lib/imsg"
import { senderDisplayName } from "@/features/messages/thread-identity"
import { messageSummary } from "@/features/messages/utils"

export function MessageReplyPreview({
  parent,
  onJump,
  onRetry,
}: {
  parent: Message | null | undefined
  onJump?: () => void
  onRetry: () => void
}) {
  const label = parent
    ? `Replying to ${parent.is_from_me ? "you" : senderDisplayName(parent)}`
    : "Replying to an earlier message"
  const content = (
    <>
      <span className="text-app-meta block font-medium text-muted-foreground">
        {label}
      </span>
      <span className="text-app-supporting mt-0.5 line-clamp-2 block break-words">
        {parent
          ? messageSummary(parent)
          : parent === null
            ? "Original message unavailable · Retry"
            : "Loading original message…"}
      </span>
    </>
  )
  const className =
    "w-full rounded-xl border border-border/70 bg-muted/45 px-3 py-2 text-left text-foreground"
  if (onJump || parent === null)
    return (
      <button
        className={`${className} hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary`}
        aria-label={
          onJump
            ? `Go to original message: ${label}`
            : "Retry loading original message"
        }
        onClick={onJump ?? onRetry}
        type="button"
      >
        {content}
      </button>
    )
  return <div className={className}>{content}</div>
}
