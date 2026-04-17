import { theme } from "../theme.ts";

/**
 * Single-line composer pinned to the bottom of the conversation column.
 *
 * We set an explicit height and `flexShrink: 0` so Yoga never squeezes this out of the
 * layout when the conversation view above it is flex-grown — that was the reason the
 * input appeared to be missing in earlier screenshots.
 *
 * The click surface around the input is intentionally wide: tapping anywhere in the
 * composer strip brings focus to the field, matching the pattern in native Messages.
 */
export function Composer({
  focused,
  value,
  onInput,
  onSubmit,
  disabled,
  status,
  onFocusRequested,
}: {
  focused: boolean;
  value: string;
  onInput: (next: string) => void;
  onSubmit: () => void;
  disabled: boolean;
  status?: string | null;
  onFocusRequested: () => void;
}) {
  const borderColor = focused ? theme.color.accent : theme.color.border;
  return (
    <box
      style={{
        width: "100%",
        height: status ? 4 : 3,
        flexShrink: 0,
        flexDirection: "column",
        paddingX: 1,
        backgroundColor: theme.color.bg,
      }}
      onMouseDown={() => {
        if (!disabled) onFocusRequested();
      }}
    >
      {status && (
        <box style={{ paddingX: 1, height: 1 }}>
          <text fg={theme.color.muted}>{status}</text>
        </box>
      )}
      <box
        style={{
          width: "100%",
          height: 3,
          flexShrink: 0,
          flexDirection: "row",
          alignItems: "center",
          borderStyle: "single",
          borderColor,
          paddingX: 1,
        }}
      >
        <text fg={focused ? theme.color.accent : theme.color.muted}>›</text>
        <box style={{ width: 1 }} />
        <input
          style={{ flexGrow: 1, backgroundColor: theme.color.bg }}
          placeholder={
            disabled ? "Select a chat to start typing…" : "Message · Enter to send"
          }
          value={value}
          focused={focused && !disabled}
          onInput={onInput}
          onSubmit={onSubmit}
          textColor={theme.color.textStrong}
          cursorColor={theme.color.accent}
          backgroundColor={theme.color.bg}
          focusedBackgroundColor={theme.color.bg}
        />
      </box>
    </box>
  );
}
