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
Scripts/create-signing-identity.sh   # once — see "Signing" below
Scripts/build-app.sh                 # release build → dist/Summon.app
Scripts/run.sh                       # debug build, then launch
open dist/Summon.app
```

Requires macOS 26 and Xcode 26 (Swift 6.1+). No external dependencies — the whole
app builds from the system SDK.

```bash
swift test                           # 126 tests over the logic layer
swift test -c release                # the same, plus the performance budgets
Scripts/selftest.sh                  # 28 runtime checks, on a fresh demo library
SUMMON_DEMO=1 SUMMON_PASTETEST=1 open -n dist/Summon.app   # real auto-paste round trip
SUMMON_DEMO=1 SUMMON_VERIFY=1   open -n dist/Summon.app   # hot key, Finder, Services, login item
SUMMON_PERF=1        swift test -c release                 # scaling measurements, no assertions
SUMMON_BUILDPROBE=1  swift test -c release                 # what dominates an index build
```

### Performance budgets

Four numbers are asserted, and they only run in a **release** build — these are
numeric loops, and a budget calibrated against an unoptimised build asserts nothing.
The suite skips itself in debug with that reason attached.

| Budget | Measured |
|---|---|
| keystroke → results, 2,000 items | 0.54 ms (budget 4 ms) |
| empty query — runs on every panel open | 0.33 ms (budget 4 ms) |
| index build, 2,000 items | 13.1 ms (budget 25 ms) |
| typing rebuilds the index | never — asserted structurally |

Budgets assert on the **fastest** of many runs, not the mean or the worst. Timing
noise is one-sided — the scheduler only ever adds time — so the minimum is the honest
estimator of what the code can do, and asserting the maximum produces a flaky suite
whose usual fix is raising the budget until it means nothing. The median and worst are
printed for drift.

`Scripts/selftest.sh` resets the demo library first, because the self-test configures
a vault and marks items sensitive; without the reset its *second* run reports failures
that are really leftovers. That reset cannot happen inside the app — the SwiftData
container is opened when the `App` struct initialises, before `applicationDidFinishLaunching`.

The self-test covers hot key registration, panel window configuration, search,
dragging, the vault lifecycle and rich-text round trips. The paste test is
separate because it needs a real Accessibility grant: it opens a scratch document
in TextEdit, summons a snippet into it, and reads the result back through the
Accessibility API to confirm the text, the substituted fill-in values and the
caret position. It refuses to run if anything but TextEdit is frontmost, so it
can never synthesise a paste into your own documents.

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
- **TCC attributes a permission to the responsible process.** Launch Summon with
  `open` rather than exec'ing `Contents/MacOS/Summon` from a shell — a binary run
  from a terminal inherits the terminal as its responsible process, and reports
  Accessibility as denied even when the grant is in place.
- **Touch ID unlock needs an Apple Developer ID.** A key guarded by
  `SecAccessControl` lives in the data-protection keychain, which requires a
  `keychain-access-groups` entitlement prefixed with a Team ID. A locally-signed
  build has no team, and adding the entitlement unprefixed makes the app fail to
  launch outright. Summon probes for this at runtime and hides the Touch ID option
  rather than offering something that cannot work; the PIN is unaffected.
- **No sync, no iOS app yet.** Deliberate: the schema is ready, the code is not.

## Signing

`Scripts/create-signing-identity.sh` creates a self-signed code-signing certificate
("Summon Local Dev") in your login keychain, and `build-app.sh` uses it when present.

This is not ceremony. TCC grants such as Accessibility are bound to an app's code
signature, and an ad-hoc signature is a hash of the binary — so every rebuild looks
like a different app and silently loses the permission. With a certificate the
designated requirement is stable:

```
identifier "com.heindewilde.summon" and certificate leaf = H"…"
```

so the grant is given once and survives every rebuild. The certificate is local
only: no other Mac trusts it, and deleting it from Keychain Access reverts the build
to ad-hoc signing with a warning.

Keychain items are bound to the signature too, so changing identity makes a
previously stored Touch ID key unreachable. The PIN still works — the vault master
key is wrapped twice, independently — and re-enabling Touch ID in Settings rewraps
it.

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
