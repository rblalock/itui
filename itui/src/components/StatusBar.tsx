import { theme } from "../theme.ts";

export type ConnectionState = "connecting" | "online" | "offline";

type Focus = "chats" | "messages" | "composer";

/**
 * Footer bar. Shows context-aware key hints for the currently focused panel plus a
 * connection indicator. Hint keys use stronger weight so the affordance stands out
 * without adding extra colour.
 */
export function StatusBar({
  focus,
  connection,
  serverURL,
  error,
}: {
  focus: Focus;
  connection: ConnectionState;
  serverURL: string;
  error?: string | null;
}) {
  const { dot, label, colour } = connectionStyle(connection);

  return (
    <box
      style={{
        width: "100%",
        height: 1,
        flexShrink: 0,
        flexDirection: "row",
        justifyContent: "space-between",
        paddingX: 1,
        backgroundColor: theme.color.surface,
      }}
    >
      <box style={{ flexDirection: "row", gap: 2 }}>
        {hintsFor(focus).map((h, i) => (
          <Hint key={i} k={h.k} d={h.d} />
        ))}
      </box>
      <box style={{ flexDirection: "row", gap: 1 }}>
        {error ? (
          <text fg={theme.color.err}>{error}</text>
        ) : (
          <>
            <text fg={colour}>{dot}</text>
            <text fg={theme.color.muted}>{label}</text>
            <text fg={theme.color.muted}>·</text>
            <text fg={theme.color.muted}>{stripProto(serverURL)}</text>
          </>
        )}
      </box>
    </box>
  );
}

function Hint({ k, d }: { k: string; d: string }) {
  return (
    <box style={{ flexDirection: "row" }}>
      <text fg={theme.color.textStrong} attributes={1}>
        {k}
      </text>
      <text fg={theme.color.muted}>{` ${d}`}</text>
    </box>
  );
}

/**
 * Which key hints to surface depends on focus. This keeps the footer short and honest —
 * no mention of `Enter send` unless the composer is actually what would send, and so on.
 */
function hintsFor(focus: Focus): { k: string; d: string }[] {
  if (focus === "composer") {
    return [
      { k: "↵", d: "send" },
      { k: "^C", d: "clear" },
      { k: "Esc", d: "close" },
    ];
  }
  if (focus === "messages") {
    return [
      { k: "i", d: "compose" },
      { k: "Esc", d: "back" },
      { k: "Tab", d: "cycle" },
      { k: "^R", d: "reload" },
      { k: "q", d: "quit" },
    ];
  }
  return [
    { k: "↑↓", d: "nav" },
    { k: "↵", d: "open" },
    { k: "i", d: "compose" },
    { k: "^N/^P", d: "prev/next" },
    { k: "^R", d: "reload" },
    { k: "q", d: "quit" },
  ];
}

function connectionStyle(c: ConnectionState) {
  if (c === "online") return { dot: "●", label: "live", colour: theme.color.ok };
  if (c === "connecting")
    return { dot: "◐", label: "connecting", colour: theme.color.warn };
  return { dot: "●", label: "offline", colour: theme.color.err };
}

function stripProto(url: string): string {
  return url.replace(/^https?:\/\//, "");
}
