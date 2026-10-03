/* eslint-disable react-refresh/only-export-components */
import * as React from "react"

import {
  BUILTIN_APP_THEMES,
  type AppThemePreset,
  DEFAULT_APP_THEME_ID,
  deriveAppTheme,
  findBuiltinTheme,
  createImportedTheme,
  parseColorsToml,
  IMPORTED_APP_THEME_ID,
  OMARCHY_LINKED_THEME_ID,
} from "@/lib/app-theme"

type ThemeProviderProps = {
  children: React.ReactNode
  defaultTheme?: string
  storageKey?: string
  disableTransitionOnChange?: boolean
}

type ThemeProviderState = {
  activeTheme: AppThemePreset
  clearImportedTheme: () => void
  fontScale: number
  importThemeFile: (file: File) => Promise<void>
  importedTheme: AppThemePreset | null
  linkedTheme: AppThemePreset | null
  setFontScale: (fontScale: number) => void
  setTheme: (themeId: string) => void
  themeId: string
  themes: AppThemePreset[]
}

type StoredThemeState = {
  fontScale: number
  importedTheme: AppThemePreset | null
  themeId: string
  linkedTheme?: AppThemePreset | null
}

const DEFAULT_FONT_SCALE = 1
const MIN_FONT_SCALE = 0.9
const MAX_FONT_SCALE = 1.3

const ThemeProviderContext = React.createContext<
  ThemeProviderState | undefined
>(undefined)

function disableTransitionsTemporarily() {
  const style = document.createElement("style")
  style.appendChild(
    document.createTextNode(
      "*,*::before,*::after{-webkit-transition:none!important;transition:none!important}"
    )
  )
  document.head.appendChild(style)

  return () => {
    window.getComputedStyle(document.body)
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        style.remove()
      })
    })
  }
}

function getLegacyThemeId(value: string) {
  if (value === "dark") {
    return "classic:night"
  }

  if (value === "light") {
    return "classic:day"
  }

  if (value === "system") {
    return window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "classic:night"
      : "classic:day"
  }

  return null
}

function isStoredImportedTheme(value: unknown): value is AppThemePreset {
  if (!value || typeof value !== "object") {
    return false
  }

  const candidate = value as Partial<AppThemePreset>
  return (
    candidate.group === "imported" &&
    typeof candidate.id === "string" &&
    typeof candidate.name === "string" &&
    typeof candidate.palette === "object" &&
    candidate.palette != null
  )
}

function readStoredThemeState(
  storageKey: string,
  defaultTheme: string
): StoredThemeState {
  try {
    const storedTheme = localStorage.getItem(storageKey)
    if (!storedTheme) {
      return {
        fontScale: DEFAULT_FONT_SCALE,
        importedTheme: null,
        themeId: defaultTheme,
      }
    }

    const legacyThemeId = getLegacyThemeId(storedTheme)
    if (legacyThemeId) {
      return {
        fontScale: DEFAULT_FONT_SCALE,
        importedTheme: null,
        themeId: legacyThemeId,
      }
    }

    const parsed = JSON.parse(storedTheme) as Partial<StoredThemeState>
    const importedTheme = isStoredImportedTheme(parsed.importedTheme)
      ? parsed.importedTheme
      : null
    const themeId =
      typeof parsed.themeId === "string" && parsed.themeId.length > 0
        ? parsed.themeId
        : defaultTheme
    const fontScale =
      typeof parsed.fontScale === "number"
        ? normalizeFontScale(parsed.fontScale)
        : DEFAULT_FONT_SCALE

    const linkedTheme =
      parsed.linkedTheme?.group === "linked" ? parsed.linkedTheme : null
    return { fontScale, importedTheme, themeId, linkedTheme }
  } catch {
    return {
      fontScale: DEFAULT_FONT_SCALE,
      importedTheme: null,
      themeId: defaultTheme,
    }
  }
}

function persistThemeState(storageKey: string, nextState: StoredThemeState) {
  try {
    localStorage.setItem(storageKey, JSON.stringify(nextState))
  } catch {
    // Ignore storage failures so theme initialization and rendering stay usable.
  }
}

export function ThemeProvider({
  children,
  defaultTheme = DEFAULT_APP_THEME_ID,
  storageKey = "theme",
  disableTransitionOnChange = true,
}: ThemeProviderProps) {
  const [{ fontScale, importedTheme, linkedTheme, themeId }, setThemeState] =
    React.useState<StoredThemeState>(() => {
      const saved = readStoredThemeState(storageKey, defaultTheme)
      return new URLSearchParams(window.location.search).get("theme") ===
        "omarchy"
        ? { ...saved, themeId: OMARCHY_LINKED_THEME_ID }
        : saved
    })

  const themes = React.useMemo(
    () => [
      ...BUILTIN_APP_THEMES,
      ...(importedTheme ? [importedTheme] : []),
      ...(linkedTheme ? [linkedTheme] : []),
    ],
    [importedTheme, linkedTheme]
  )

  React.useEffect(() => {
    let cancelled = false
    let generation = 0
    const receive = (payload: {
      theme?: { name: string; colors: Record<string, string> } | null
    }) => {
      if (cancelled || !payload.theme) return
      try {
        const palette = parseColorsToml(
          Object.entries(payload.theme.colors)
            .map(([key, value]) => `${key} = ${JSON.stringify(value)}`)
            .join("\n")
        )
        const next: AppThemePreset = {
          id: OMARCHY_LINKED_THEME_ID,
          group: "linked",
          name: "Follow Omarchy",
          palette,
        }
        setThemeState((state) => {
          const updated = { ...state, linkedTheme: next }
          persistThemeState(storageKey, updated)
          return updated
        })
      } catch {
        // Preserve the last valid palette during a failed or malformed update.
      }
    }
    const refresh = () => {
      const requestGeneration = ++generation
      void fetch("/api/theme", { cache: "no-store" })
        .then((response) => {
          if (!response.ok) throw new Error("Theme unavailable")
          return response.json()
        })
        .then((payload) => {
          if (generation === requestGeneration) receive(payload)
        })
        .catch(() => {})
    }
    const events = new EventSource("/api/state/events")
    events.addEventListener("theme", (event) => {
      try {
        generation += 1
        receive(JSON.parse((event as MessageEvent).data))
      } catch {
        /* Keep cached palette. */
      }
    })
    events.addEventListener("contacts", () =>
      window.dispatchEvent(new Event("itui:contacts-changed"))
    )
    events.addEventListener("open", refresh)
    const onVisible = () => {
      if (!document.hidden) refresh()
    }
    window.addEventListener("focus", refresh)
    document.addEventListener("visibilitychange", onVisible)
    refresh()
    return () => {
      cancelled = true
      events.close()
      window.removeEventListener("focus", refresh)
      document.removeEventListener("visibilitychange", onVisible)
    }
  }, [storageKey])

  const activeTheme =
    themes.find((theme) => theme.id === themeId) ??
    importedTheme ??
    findBuiltinTheme(defaultTheme) ??
    BUILTIN_APP_THEMES[0]

  const setTheme = React.useCallback(
    (nextThemeId: string) => {
      setThemeState((currentState) => {
        const resolvedThemeId =
          nextThemeId === IMPORTED_APP_THEME_ID &&
          currentState.importedTheme == null
            ? defaultTheme
            : nextThemeId
        const nextState = {
          ...currentState,
          themeId: resolvedThemeId,
        }
        persistThemeState(storageKey, nextState)
        return nextState
      })
    },
    [defaultTheme, storageKey]
  )

  const clearImportedTheme = React.useCallback(() => {
    setThemeState((currentState) => {
      const nextState = {
        ...currentState,
        importedTheme: null,
        themeId:
          currentState.themeId === IMPORTED_APP_THEME_ID
            ? defaultTheme
            : currentState.themeId,
      }
      persistThemeState(storageKey, nextState)
      return nextState
    })
  }, [defaultTheme, storageKey])

  const setFontScale = React.useCallback(
    (nextFontScale: number) => {
      setThemeState((currentState) => {
        const nextState = {
          ...currentState,
          fontScale: normalizeFontScale(nextFontScale),
        }
        persistThemeState(storageKey, nextState)
        return nextState
      })
    },
    [storageKey]
  )

  const importThemeFile = React.useCallback(
    async (file: File) => {
      const contents = await file.text()
      const importedPalette = parseColorsToml(contents)
      const nextImportedTheme = createImportedTheme(file.name, importedPalette)

      setThemeState((currentState) => {
        const nextState = {
          ...currentState,
          importedTheme: nextImportedTheme,
          themeId: nextImportedTheme.id,
        }
        persistThemeState(storageKey, nextState)
        return nextState
      })
    },
    [storageKey]
  )

  const applyTheme = React.useCallback(
    (theme: AppThemePreset, nextFontScale: number) => {
      const root = document.documentElement
      const { cssVariables, mode } = deriveAppTheme(theme.palette)
      const restoreTransitions = disableTransitionOnChange
        ? disableTransitionsTemporarily()
        : null

      root.classList.remove("light", "dark")
      root.classList.add(mode)
      root.style.colorScheme = mode
      root.dataset.appTheme = theme.id
      root.style.setProperty(
        "--app-font-scale",
        String(normalizeFontScale(nextFontScale))
      )

      for (const [key, value] of Object.entries(cssVariables)) {
        root.style.setProperty(key, value)
      }

      if (restoreTransitions) {
        restoreTransitions()
      }
    },
    [disableTransitionOnChange]
  )

  React.useLayoutEffect(() => {
    applyTheme(activeTheme, fontScale)
  }, [activeTheme, applyTheme, fontScale])

  React.useEffect(() => {
    const handleStorageChange = (event: StorageEvent) => {
      if (event.storageArea !== localStorage || event.key !== storageKey) {
        return
      }

      setThemeState(readStoredThemeState(storageKey, defaultTheme))
    }

    window.addEventListener("storage", handleStorageChange)

    return () => {
      window.removeEventListener("storage", handleStorageChange)
    }
  }, [defaultTheme, storageKey])

  const value = React.useMemo(
    () => ({
      activeTheme,
      clearImportedTheme,
      fontScale,
      importThemeFile,
      importedTheme,
      linkedTheme: linkedTheme ?? null,
      setFontScale,
      setTheme,
      themeId: activeTheme.id,
      themes,
    }),
    [
      activeTheme,
      clearImportedTheme,
      fontScale,
      importThemeFile,
      importedTheme,
      linkedTheme,
      setFontScale,
      setTheme,
      themes,
    ]
  )

  return (
    <ThemeProviderContext.Provider value={value}>
      {children}
    </ThemeProviderContext.Provider>
  )
}

export function useAppTheme() {
  const context = React.useContext(ThemeProviderContext)
  if (context === undefined) {
    throw new Error("useAppTheme must be used within a ThemeProvider")
  }

  return context
}

function normalizeFontScale(value: number) {
  return Math.min(
    MAX_FONT_SCALE,
    Math.max(MIN_FONT_SCALE, Number(value.toFixed(2)))
  )
}
