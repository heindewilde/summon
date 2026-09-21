# Sandbox Spike A

*2026-09-04. Throwaway branch, discarded. Run before committing to iCloud sync,
because iCloud entitlements are generally taken to require App Sandbox on macOS —
and Summon is unsandboxed on purpose, to read the Finder selection over Apple Events
and to paste into other apps.*

**Verdict: sandboxing is survivable. The cost is not an entitlement, it is the data.**

## What was changed

`Scripts/build-app.sh`'s entitlements heredoc only:

```diff
-    <key>com.apple.security.app-sandbox</key><false/>
+    <key>com.apple.security.app-sandbox</key><true/>
     <key>com.apple.security.automation.apple-events</key><true/>
+    <key>com.apple.security.files.user-selected.read-write</key><true/>
+    <key>com.apple.security.temporary-exception.apple-events</key>
+    <array><string>com.apple.finder</string></array>
```

Same signing identity, same bundle path, same bundle ID.

## What survived

| | |
|---|---|
| Launches sandboxed | ✅ |
| `Scripts/selftest.sh` | ✅ 90/90 |
| Global hot keys register (⌥Space, ⌥⇧S) | ✅ both — Carbon needs no entitlement, as designed |
| Finder driven over Apple Events | ✅ with the temporary exception |
| Finder selection readable | ✅ `Quarterly report.txt` |
| ⌥⇧S captures the selection as files | ✅ |
| "Add to Summon" in the Services registry | ✅ |
| PDFKit / Vision extraction | ✅ 642 characters, search reaches inside |

The Apple Events result is the one that mattered. `SelectionCapture.finderSelection()`
is the single capability most obviously threatened by the sandbox, and the temporary
exception scoped to `com.apple.finder` preserves it. That entitlement would be an App
Store rejection; it is fine for Developer ID, which is the distribution channel.

## What was not tested, and why

**CGEvent ⌘V synthesis, and the TextEdit paste round trip.** These need synthetic
keystrokes on a live machine, and the machine was in use. Judged low-risk to defer:
event posting is gated on Accessibility, which the sandbox does not mediate.
**Re-test in Phase 7**, where the Developer ID re-sign forces a re-test anyway.

**Whether Summon's own Accessibility grant survives the entitlement change.**
`selftest.sh` reported `Accessibility granted: yes` under the sandbox, but it launches
the binary directly from a shell, and the README's own Known Limits note says a binary
exec'd from a terminal inherits the terminal as responsible process. So that line may
be reporting the terminal's grant. **Treat as unproven.** It is moot either way: the
Phase 7 re-sign to Developer ID invalidates the grant regardless, and it is re-granted
once.

## The actual cost: the library moves

Sandboxing relocates Application Support into the container. The sandboxed build
found no library and seeded a fresh starter one:

```
~/Library/Containers/com.heindewilde.summon/Data/Library/Application Support/Summon/
```

The real library at `~/Library/Application Support/Summon` was untouched — verified
before and after at 4 items, 5 folders, 19 tags. Nothing was lost, but nothing was
carried across either: **a sandboxed build silently starts empty.** For anyone already
using Summon that is the whole of the risk, and it is a data-migration problem rather
than a plist problem.

## What follows

1. **Do the relocation once, and do it for the App Group** — `<TeamID>.group.…`, which
   Phase 6 needs anyway so extensions can reach the store. Sandboxing then becomes a
   separate, cheap decision rather than its own migration.
2. `LibraryPaths.standard()` only redirects *new* libraries. A
   `LibraryPaths.relocateIfNeeded()` is required: move an existing root, verify, leave
   a marker. Same backup-verify-delete discipline as the Phase 5 blob migration.
3. **Spike B still has to happen** (Phase 7): whether iCloud entitlements work on an
   *unsandboxed* Developer ID build. If they do, none of the above is forced. This
   spike only establishes that the fallback is viable — which is what makes the sync
   decision safe to keep.

## Cleanup

Branch deleted, container removed, `dist/Summon.app` rebuilt unsandboxed and relaunched.
