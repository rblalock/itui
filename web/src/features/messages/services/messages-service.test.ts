import { describe, expect, it, vi } from "vitest"
import { ImsgClient } from "@/lib/imsg"
import { MessagesService } from "@/features/messages/services/messages-service"

describe("reply parent lookup", () => {
  it("keeps large lookups within the API limit and preserves the conversation", async () => {
    const client = new ImsgClient()
    const lookup = vi.spyOn(client, "listMessages").mockResolvedValue([])
    const guids = Array.from({ length: 101 }, (_, index) => `parent-${index}`)
    await new MessagesService(client).listMessagesByGuids(7, guids)
    expect(lookup).toHaveBeenCalledTimes(2)
    expect(lookup).toHaveBeenNthCalledWith(1, 7, {
      guids: guids.slice(0, 100),
      limit: 100,
    })
    expect(lookup).toHaveBeenNthCalledWith(2, 7, {
      guids: guids.slice(100),
      limit: 1,
    })
  })

  it("does not fetch normal history when there are no parents to look up", async () => {
    const client = new ImsgClient()
    const lookup = vi.spyOn(client, "listMessages").mockResolvedValue([])
    expect(
      await new MessagesService(client).listMessagesByGuids(7, [])
    ).toEqual([])
    expect(lookup).not.toHaveBeenCalled()
  })
})
