# itui

iMessage in your terminal. Run the server on your Mac, connect from anywhere.

```
┌─ Chats ─────────────────────┐┌──────────── jess 💕 · +13214808737 ───────────┐
│ ● jess 💕            9:48a  ││                  ── Today ──                   │
│   Joe Vogel           9:41a ││                                                │
│   Poke 🌴            9:16a ││  Beef and broccoli tonight ?                   │
│   Exi                 7:20a ││  Did you get a rice cooker                     │
│   Sequence            3:25a ││  3:10 PM                                       │
│                             ││                          Yeah sounds great     │
│                             ││                                    3:10 PM     │
│                             │├────────────────────────────────────────────────┤
│                             ││ › Message · Enter to send                      │
└─────────────────────────────┘└────────────────────────────────────────────────┘
 ↑↓ nav  ↵ open  i compose  ^N/^P prev/next  ^R reload  q quit  ● live · :8080
```

## Install

One command:

```bash
curl -fsSL https://raw.githubusercontent.com/R44VC0RP/itui/main/install.sh | bash
```

Or clone and run manually:

```bash
git clone https://github.com/R44VC0RP/itui.git
cd itui
./install.sh
```

The installer:
- Builds the `imsg` server binary (Swift, macOS)
- Installs the `itui` TUI client (Bun + OpenTUI)
- Puts both commands in `~/.local/bin`
- Creates `~/.config/itui/config.json` with defaults

### Requirements

**Server (macOS only)**
- macOS 14+ with Messages.app signed in
- Xcode Command Line Tools (`xcode-select --install`)
- Full Disk Access for your terminal (System Settings → Privacy → Full Disk Access)

**Client (any platform)**
- [Bun](https://bun.sh) (`curl -fsSL https://bun.sh/install | bash`)

## Quick start

```bash
# 1. Start the server on your Mac
imsg serve

# 2. Open the TUI (same machine, or any machine that can reach :8080)
itui
```

## Remote access

The server runs on your Mac. Connect from anywhere:

```bash
# SSH tunnel from your laptop
ssh -N -L 8080:127.0.0.1:8080 you@your-mac.local

# Then just run itui — it connects to localhost:8080 by default
itui
```

Or point directly at a host on your network:

```bash
itui --server=http://mac-mini.local:8080
# or persist it:
itui config set server=http://mac-mini.local:8080
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Your Mac                           │
│                                                         │
│  Messages.app ← → chat.db ← → imsg serve (:8080)       │
│                                    │                    │
│                    ┌───────────────┼───────────────┐    │
│                    │ HTTP API      │ SSE stream    │    │
│                    │ /api/chats    │ /api/events   │    │
│                    │ /api/send     │               │    │
│                    │ /api/contacts │               │    │
│                    └───────────────┼───────────────┘    │
└────────────────────────────────────┼────────────────────┘
                                     │
                            ┌────────┴────────┐
                            │    itui (TUI)   │
                            │  runs anywhere  │
                            └─────────────────┘
```

**`imsg serve`** — Swift HTTP server that reads `chat.db`, resolves contacts + avatars, and exposes a full REST + SSE API. Runs on your Mac next to Messages.app.

**`itui`** — OpenTUI (React) terminal client. Connects to the server over HTTP. Runs on any machine with Bun.

## Keyboard shortcuts

### Sidebar focused

| Key | Action |
| --- | --- |
| `↑` / `↓` or `k` / `j` | Navigate chats |
| `Enter` / `→` / `l` | Open chat |
| `i` or `c` | Jump to composer |

### Messages focused

| Key | Action |
| --- | --- |
| `Esc` / `←` / `h` | Back to sidebar |
| `i` or `Enter` | Jump to composer |

### Composer focused

| Key | Action |
| --- | --- |
| `Enter` | Send message |
| `Ctrl+C` | Clear input (or close if empty) |
| `Esc` | Close composer |

### Global

| Key | Action |
| --- | --- |
| `Tab` / `Shift+Tab` | Cycle panels |
| `Ctrl+N` / `Ctrl+P` | Next / previous chat |
| `Ctrl+R` | Reload chat list |
| `q` or `Ctrl+C` | Quit (outside composer) |

## Configuration

Config lives at `~/.config/itui/config.json`:

```json
{
  "server": "http://127.0.0.1:8080",
  "token": null,
  "defaultChatId": null,
  "reconnectDelayMs": 2000
}
```

```bash
itui config                         # show current config
itui config set server=http://...   # update a key
itui config set token=bearer-xxx    # set auth token (future)
itui config reset                   # restore defaults
itui config path                    # print config file path
```

## API endpoints

The `imsg serve` HTTP API can be used by any client, not just `itui`.

| Endpoint | Description |
| --- | --- |
| `GET /api/chats` | List chats with resolved contacts |
| `GET /api/chats/:id/messages` | Messages with sender contacts + attachment URLs |
| `GET /api/contacts` | All resolved contacts (name, initials, avatar) |
| `GET /api/contacts/resolve?handle=...` | Resolve a single handle |
| `GET /api/contacts/avatar?handle=...` | Stream avatar image |
| `GET /api/attachments/:id` | Stream attachment file |
| `GET /api/events` | SSE stream of new messages |
| `POST /api/send` | Send a message |
| `GET /debug` | Debug page for verifying contacts + avatars |

## CLI commands (imsg)

```bash
imsg chats [--limit 20] [--contacts] [--json]
imsg history --chat-id <id> [--limit 50] [--contacts] [--attachments] [--json]
imsg watch [--chat-id <id>] [--contacts] [--attachments] [--json]
imsg send --to <handle> --text "hi" [--service imessage|sms|auto]
imsg contacts [--handle +15551234567] [--json]
imsg serve [--host 127.0.0.1] [--port 8080]
imsg rpc   # JSON-RPC over stdio
```

## macOS permissions

On first run, macOS will prompt you for:

1. **Full Disk Access** — required to read `~/Library/Messages/chat.db`. Grant to your terminal app in System Settings → Privacy & Security → Full Disk Access.

2. **Contacts** — optional, for resolving names + avatars. A prompt appears on first use; deny and handles show as phone numbers.

3. **Automation (Messages.app)** — required only for sending. A prompt appears on first send.

## Development

```bash
# Server
make build              # release build → bin/imsg
make test               # run Swift tests
make lint               # swift-format + swiftlint

# Client
cd itui
bun install
bun run src/cli.tsx     # run in dev mode
bun run typecheck       # tsc --noEmit
```

## Credits

Server built on [steipete/imsg](https://github.com/steipete/imsg). TUI built with [OpenTUI](https://opentui.com).

## License

MIT
