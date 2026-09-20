# App Store listing

Everything App Store Connect asks for, written out. Paste rather than compose.

One record, both platforms (universal purchase): **iOS + macOS**, bundle ID
`com.heindewilde.summon`, price **Free**.

---

## Name (30 characters)

```
Summon
```

## Subtitle (30 characters)

```
Everything you reuse, fast
```

## Promotional text (170 characters — changeable without review)

```
The reply you keep rewriting, the IBAN, the passport scan. One keystroke on the Mac, one tap on your phone, and it is on the clipboard where you need it.
```

## Description (4,000 characters)

```
Summon holds the handful of things you reuse — the canned reply, the IBAN, the VAT number, the passport scan, the portfolio PDF — and gets one of them to you in about a second.

On the Mac, press ⌥Space in any app, type a few letters, press ↩, and it is pasted where your cursor already was. No window to find, no tab to switch to, no clipboard to babysit. On iPhone and iPad, tap an item and it is on the clipboard, ready to paste wherever you were going.

Because Summon holds less than a notes app, it can be much better at the one moment that matters.

FAST
• A keystroke re-ranks 2,000 items in about half a millisecond — measured by the test suite, not claimed
• Results are ranked by what you actually reach for, and by what you have used in this app before
• Fuzzy search that reaches inside PDFs and images, so a phrase on page four is one search away

EVERYTHING IN ONE PLACE
• Snippets, rich text, images, PDFs and whole files
• Nested folders with their own icon and colour, tags that cut across them, pins for what you need most
• Fill-in fields: "Hi {{first_name}}" turns into a small form. Dates, times and the clipboard fill themselves in

ON EVERY DEVICE
• Your library syncs through your own iCloud — there is no Summon account and no Summon server
• Save into Summon from any app's share sheet, or from Finder's Quick Actions
• A widget of pinned items that copies on tap, plus Shortcuts, Siri and a Control Centre button
• Spotlight finds your items — except the ones you have marked sensitive, which are never indexed

PRIVATE BY DESIGN
• No account, no analytics, no tracking, no ads
• Mark anything sensitive and it is encrypted on your device with AES-GCM, under a key Apple never sees
• A locked item stays findable by name and reveals nothing of its contents, its file, or the text inside a scan
• Unlock with a PIN, a passphrase, Face ID or Touch ID
• "Encrypt everything" applies the same protection to your whole library, including what syncs

OPEN SOURCE
Every claim here can be checked: the source is on GitHub under the AGPL-3.0 licence.

Requires macOS 26 or iOS 26.
```

## Keywords (100 characters, comma-separated, no spaces)

```
snippets,clipboard,paste,productivity,text,expander,shortcuts,templates,notes,files,pdf,private
```

## Support URL

```
https://summon.technology/support
```

## Marketing URL

```
https://summon.technology
```

## Privacy Policy URL

```
https://summon.technology/privacy
```

## Category

Primary: **Productivity**. Secondary: **Utilities**.

## Age rating

4+. No objectionable content, no user-generated content shared between people, no web
browsing.

---

## App privacy ("nutrition label")

**Data Not Collected** — every question. Summon has no analytics, no accounts, and no
server; sync is performed by the system into the owner's own private CloudKit database,
which the developer cannot read.

Declare crash reporting only if you later enable it; Apple's own crash sharing is the
device owner's setting, not data Summon collects.

## Export compliance

`ITSAppUsesNonExemptEncryption` is already `false` in both apps' Info.plists. Summon
uses Apple's own CryptoKit to protect the owner's data on their own device, which is
exempt.

---

## Review notes

```
Summon is a library of things you reuse, with one purchase covering Mac, iPhone and iPad.

ACCESSIBILITY PERMISSION (macOS)
The Mac app asks for Accessibility for exactly one purpose: after you choose an item, it
sends a single ⌘V to the app you were using, so the item lands where your cursor already
was. It does not read the screen, observe typing, or record anything. Without the
permission the app copies the item and shows "Press ⌘V" instead — the app is fully
functional either way, and the permission is requested at the moment it would first help,
never at launch.

ICLOUD
Sync uses the owner's own private CloudKit database. There is no account to create and no
server operated by the developer. Items marked sensitive are encrypted on-device before
they sync, with a key held in iCloud Keychain.

HOW TO TRY IT
1. Open the app; the library starts empty.
2. Add something: the + button offers a new snippet, files, a photo, or "save what I
   copied".
3. Tap the item. It is copied to the clipboard — paste it into Notes to confirm.
4. Tap the chevron to read it, Edit to change it.
5. The share sheet in Safari or Files offers "Add to Summon".

No demo account is required.
```

## What's new (first release)

```
The first release. Summon on Mac, iPhone and iPad, with your library syncing through
your own iCloud.
```

---

## Screenshots

In `docs/screenshots/appstore/`, captured from the demo library — no real data.

| Where | Size Apple asks for | Have |
|---|---|---|
| iPhone | 6.9" (1320 × 2868) | `iphone-home`, `iphone-detail`, `iphone-fill`, `iphone-settings` |
| iPad | 13" (2064 × 2752) | `ipad-home` |
| Mac | 2880 × 1800 | `docs/screenshots/*.png` — the panel, the library, the action menu |

Re-capture with the recipe in `docs/screenshots/appstore/README.md`.
