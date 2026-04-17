/**
 * Design tokens for itui.
 *
 * The palette is deliberately tight — one accent, one warning, and a neutral scale. The
 * rest of the interface leans on typographic weight and spacing to establish hierarchy,
 * which tracks how ui.sh / Refactoring UI recommend building interfaces: limit colour,
 * earn it, and let whitespace do the work.
 */
export const theme = {
  color: {
    // Neutral scale — from backdrop (darkest) to primary text (lightest).
    bg: "#0b0d11",
    surface: "#14171d",
    surfaceHover: "#1a1e26",
    surfaceActive: "#232833",
    border: "#262b36",
    borderStrong: "#323846",
    muted: "#6b7180",
    text: "#dadde5",
    textStrong: "#f6f7fa",

    // Accents — used sparingly, with meaning.
    /// iMessage blue — reserved for "your" outgoing bubble + selection highlight.
    accent: "#1982fc",
    accentDim: "#12508f",
    /// Used for send / success confirmation.
    ok: "#38d399",
    /// Used for disconnect / errors only.
    err: "#f5626c",
    /// Used for unread dot.
    warn: "#f5c16c",
  },
  space: {
    gutter: 1,
    section: 2,
  },
} as const;

export type Theme = typeof theme;
