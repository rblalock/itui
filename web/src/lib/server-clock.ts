let offsetMs = 0

export function noteServerDate(value: string | null) {
  if (!value) return
  const timestamp = Date.parse(value)
  if (Number.isFinite(timestamp)) offsetMs = timestamp - Date.now()
}

export function serverNowISO() {
  return new Date(Date.now() + offsetMs).toISOString()
}
