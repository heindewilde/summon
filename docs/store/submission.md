# Submitting Summon

The order matters in two places: the CloudKit schema is append-only once promoted, and
the release entitlements only take effect through a distribution build. Everything else
can be done in any order.

## Before the first upload

- [ ] **Version and build numbers.** `MARKETING_VERSION` 1.0 in both apps;
      `CURRENT_PROJECT_VERSION` has to increase with every upload, including TestFlight
      builds that are never released.
- [ ] **Promote the CloudKit schema to Production** — CloudKit Console → the
      `iCloud.com.heindewilde.summon` container → Schema → *Deploy Schema Changes*.
      After this, fields can be added but never removed or renamed, so nothing about the
      model should still be in flux.
- [ ] **Check the release entitlements.** A Release build takes
      `Apps/SummonPhone/SummonPhone-Release.entitlements` and
      `Apps/SummonMac/SummonMac-Release.entitlements`, which carry `production` push.
      A local Release build still shows `development` because it is signed with a
      development profile; the distribution profile is what makes it production.

## Upload

`Scripts/ship.sh` does all three steps from the command line once the credentials
exist:

```sh
Scripts/ship.sh archive          # no credentials needed
export SUMMON_ASC_KEY_ID=…       # from App Store Connect → Users and Access → Integrations
export SUMMON_ASC_ISSUER_ID=…
Scripts/ship.sh upload           # exports with the distribution profile, then uploads
xcrun cktool save-token --type management   # once, from CloudKit Console → Settings → Tokens
Scripts/ship.sh promote-schema   # asks before the one-way step
```

The API key (`AuthKey_<KEY_ID>.p8`) belongs in `~/.appstoreconnect/private_keys/` and
is downloadable only once.

Or through Xcode, which uses your own session instead:

1. **Product → Archive** with the `SummonMac` scheme, then the `SummonPhone` scheme
   (choose *Any iOS Device* first).
2. **Window → Organizer → Distribute App → App Store Connect → Upload.**
3. Let Xcode manage signing; it creates the distribution profiles.

If Organizer reports a missing capability, the App ID at
[developer.apple.com](https://developer.apple.com/account/resources/identifiers) needs
it enabled — the app uses App Groups, iCloud (CloudKit), Push Notifications and a
keychain group.

## In App Store Connect

`Scripts/asc.py` does all of this except the privacy questionnaire, which the API does
not expose:

```sh
Scripts/asc.py metadata      # description, keywords, subtitle, URLs — both platforms
Scripts/asc.py screenshots   # docs/screenshots/appstore → the listing
Scripts/asc.py ready         # what Apple still wants, asked of Apple
```

Already set for version 1.0: categories (Productivity, Utilities), the age
questionnaire at 4+, price (free, base territory Netherlands), both builds attached to
their versions, and the review contact and notes.

- [ ] **App privacy:** *Data Not Collected*, every question. The only part of the
      listing with no API, so it is a browser job: App Store Connect › App Privacy.

## TestFlight

- [ ] Internal testing first — it needs no review.
- [ ] External testing goes through a beta review, usually a day.
- [ ] Test on a device that has **never** run a development build: a fresh install is
      the only way to see the first-run experience, the empty states, and whether sync
      populates a new device from scratch.

## Then submit

Submit iOS and macOS together, so one purchase covers both from the first day.

## If review pushes back on pasting

The Mac app synthesises ⌘V, which needs Accessibility. Build with `SUMMON_COPY_ONLY`
defined and the whole path turns off: Summon copies and shows "Press ⌘V" instead, which
the app already does when the permission is absent. The switch exists precisely so this
is a rebuild rather than a redesign.

## Afterwards

- [ ] Set `appStore` in `summon-web/src/lib/site.ts` to the listing URL, so the website's
      button stops saying "coming soon".
- [ ] Tag the release.
