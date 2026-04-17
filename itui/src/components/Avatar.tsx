import { theme } from "../theme.ts";
import type { ResolvedContact } from "../api/types.ts";

/**
 * Terminals can't render images reliably across every emulator, so we render an initials
 * chip instead. Background is derived from the handle so the same person always gets the
 * same colour — a cheap trick that makes group chats scannable without any art.
 */
export function Avatar({
  contact,
  handle,
  size = 3,
}: {
  contact?: ResolvedContact;
  handle?: string;
  size?: number;
}) {
  const initials = (contact?.initials || initialsFromHandle(contact?.name ?? handle ?? "")).slice(0, 2);
  const key = contact?.handle ?? handle ?? "";
  const bg = pickBg(key);
  const label = initials.length > 0 ? initials : "•";
  return (
    <box
      style={{
        width: size,
        height: size - 2 > 0 ? size - 2 : 1,
        backgroundColor: bg,
        justifyContent: "center",
        alignItems: "center",
        paddingX: 1,
      }}
    >
      <text fg={theme.color.textStrong} attributes={1 /* bold */}>
        {label}
      </text>
    </box>
  );
}

function initialsFromHandle(value: string): string {
  const letters = value.match(/[A-Za-z]+/g);
  if (!letters || letters.length === 0) return "";
  if (letters.length >= 2) {
    return `${letters[0]![0]}${letters[1]![0]}`.toUpperCase();
  }
  return letters[0]!.slice(0, 2).toUpperCase();
}

// Small curated palette — all readable on dark backgrounds, none competing with the
// iMessage blue accent used for outgoing bubbles/selection.
const AVATAR_BGS = [
  "#3a4960",
  "#4a4068",
  "#4a5a3a",
  "#603a4a",
  "#3a5a5a",
  "#5a4a3a",
  "#4a3a60",
  "#506a4a",
];

function pickBg(key: string): string {
  let h = 0;
  for (let i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) >>> 0;
  return AVATAR_BGS[h % AVATAR_BGS.length]!;
}
