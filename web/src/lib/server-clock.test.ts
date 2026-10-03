import { afterEach, expect, it, vi } from "vitest"
import { noteServerDate, serverNowISO } from "@/lib/server-clock"

afterEach(() => {
  vi.useRealTimers()
  noteServerDate(new Date().toUTCString())
})

it("uses the Mac clock when the Linux clock differs", () => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date("2026-10-03T12:05:00Z"))
  noteServerDate("Sat, 03 Oct 2026 12:00:00 GMT")
  expect(serverNowISO()).toBe("2026-10-03T12:00:00.000Z")
  noteServerDate("invalid")
  expect(serverNowISO()).toBe("2026-10-03T12:00:00.000Z")
})
