# Summon

One place for the things you reuse — canned replies, documents you show clients,
the details you paste into forms — and one shortcut to put any of them exactly
where your cursor already is.

Summon is narrower than a notes app: it isn't where you write. It's narrower than a
file manager: it isn't where you keep everything. It holds only what you reach for
repeatedly, and optimises hard for the moment of retrieval.

**Everything stays on this Mac.** No accounts, no sync, no network requests.

## Build and run

```bash
Scripts/build-app.sh          # release build → dist/Summon.app
Scripts/run.sh                # debug build, then launch
open dist/Summon.app
```

Requires macOS 26 and Xcode 26 (Swift 6.1+). No external dependencies — the whole
app builds from the system SDK.

```bash
swift test                    # 103 tests over the logic layer
SUMMON_SELFTEST=1 SUMMON_DEMO=1 ./dist/Summon.app/Contents/MacOS/Summon
```

`SUMMON_DEMO=1` points the app at a throwaway library (`Summon-Demo`) so you can
experiment without touching your real one.

## The keyboard model

| Key | Does |
|---|---|
| `⌥Space` | Summon the panel from anywhere |
| `⌥⇧S` | Save whatever is selected right now, without leaving the app you're in |
| `↩` | Paste into the app you were just in |
| `⌘↩` | Copy instead |
| `⌥↩` | Open the file |
| `⇧↩` | Paste as plain text |
| `⌘1`–`⌘9` | Jump straight to a result |
| `⎋` | Close |

Filter as you type: `#tag`, `/folder`, `img:`, `pdf:`, `txt:`, `file:`.

Snippets can contain fill-in fields — `{{first_name}}`, `{{topic:your enquiry}}` —
plus `{{date}}`, `{{date:+3d}}`, `{{time}}`, `{{clipboard}}` and `{{cursor}}`.
Choosing a snippet with fields turns the panel into a small form; the caret lands
where `{{cursor}}` was.

## Architecture

```
Sources/
  SummonKit/     Pure logic. No views. The entire test surface.
    Model/       SwiftData models, LibraryStore, starter library
    Vault/       AES-GCM sealing, PIN wrapping, Touch ID, lock lifecycle
    Storage/     Managed blob store, content hashing, scratch materialisation
    Search/      Fuzzy scorer, frecency, app affinity, query parser
    Snippets/    Placeholder parsing and rendering
    Intelligence/ Heuristics, Vision/PDF extraction, on-device model
    Capture/     Clipboard monitor, selection capture, importer
    Insertion/   Pasteboard writing, focus restore, synthetic paste
    HotKeys/     Carbon RegisterEventHotKey wrapper
  SummonUI/      SwiftUI views and the design system
  Summon/        Executable: panel window, menu bar, scenes, wiring
```

SwiftData models are main-actor bound and not `Sendable`, so ranking works on
`ItemSnapshot` value types instead. That keeps concurrency simple *and* makes the
whole search layer testable without a store.

The schema follows CloudKit's rules from day one — no unique constraints, every
relationship optional with an inverse, every attribute defaulted — so the planned
iOS companion is additive rather than a migration. No sync code ships today.

## How sensitive items work

Marking an item or folder sensitive encrypts it:

- A random 256-bit master key is generated once. Per-item keys derive from it via
  HKDF using the item's UUID, so no key is ever reused across two items.
- The master key is wrapped twice: under your PIN (PBKDF2-SHA256, 600k iterations)
  and in the Keychain behind Touch ID. Changing the PIN re-wraps one key, so it's
  instant.
- Unlocked, the key lives in memory only. It's discarded on lock, on a timeout, and
  on sleep. Decrypted scratch copies are wiped at the same moment.
- Five wrong PINs start an escalating cooldown.

**Titles stay visible; contents do not.** A locked item is findable by name and tag
but matches nothing in its body, its file, or its OCR'd text — that last one is what
stops a locked passport scan being found by searching its own contents. Sensitive
content is never handed to the language model, even though the model is local.

## Intelligence

On-device only, and never load-bearing:

- **Vision** OCRs images and extracts PDF text, so contents are searchable.
- **FoundationModels** suggests a title, tags and a summary on import, and rewrites
  snippets in a different register.

If Apple Intelligence is unavailable, every one of these falls back to deterministic
heuristics. Settings shows the real status rather than pretending.

## Known limits

- **Auto-paste needs Accessibility.** Global shortcuts do not — those use Carbon's
  `RegisterEventHotKey` and work immediately. Accessibility is used for exactly one
  thing: pressing ⌘V for you. Without it Summon copies and shows "press ⌘V", which
  is one extra keystroke and nothing else.
- **Ad-hoc signing changes the code hash on every build**, so macOS may drop the
  Accessibility grant after a rebuild. `dist/Summon.app` is a stable path to
  minimise this; signing with a Developer ID and notarising removes it permanently
  (not set up here — v1 is deliberately ad-hoc signed for local use).
- **No sync, no iOS app yet.** Deliberate: the schema is ready, the code is not.

## Development notes

`SUMMON_SNAPSHOT=<dir>` renders each surface to PNG for design review. It uses
`ImageRenderer`, which draws SwiftUI's own layout but cannot draw AppKit-backed
containers, so the library window (`NavigationSplitView` + `List`) has to be
reviewed live. `SnapshotSafeScrollView` and `EnvironmentValues.isSnapshotting`
exist only to serve that harness; behaviour in the shipped app is unchanged.

`SUMMON_LIVE=library|grid|detail|panel|menubar|settings` puts that surface on
screen in a real window and writes its window number to `SUMMON_LIVE_INFO`, so it
can be captured with `screencapture -l` — one window, not the whole screen.
`SUMMON_APPEARANCE=dark` forces this app's appearance only, leaving the system
setting alone:

```bash
SUMMON_DEMO=1 SUMMON_LIVE=library SUMMON_LIVE_INFO=/tmp/win \
  open -n dist/Summon.app && sleep 6 && \
  screencapture -o -l "$(cat /tmp/win)" library.png
```
