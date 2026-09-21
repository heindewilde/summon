# App Store screenshots

Captured from the simulator against the demo library — no real data, which is also why
the numbers in them are an example IBAN rather than anyone's.

**Look at every frame before uploading.** The first set went to the App Store showing
nothing but a loading spinner: a Debug build on a cold simulator takes longer to open
its library than the capture waited, and a screenshot of a spinner looks exactly like a
screenshot until someone opens it. `asc.py screenshots` cannot tell the difference.

- `iphone-*.png` — iPhone 17 Pro (6.9"), dark
- `ipad-home.png` — iPad Pro 13", dark
- `main-window-dark.png`, `panel-search-dark.png` — Mac, 2160 × 1360, from the Mac's own
  snapshot harness (`SUMMON_DEMO=1 SUMMON_SNAPSHOT=<dir> dist/Summon.app/Contents/MacOS/Summon`).
  The Mac App Store wants 2880 × 1800; scale up or re-render at that size. The harness
  writes inside the app's container now that the app is sandboxed, and says where.

Re-capture after a UI change:

```sh
# The demo library the shots use
Scripts/selftest.sh

DEVICE=<simulator udid>
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --wifiBars 3
for screen in home detail fill settings; do
  xcrun simctl terminate "$DEVICE" com.heindewilde.summon
  xcrun simctl launch "$DEVICE" com.heindewilde.summon -app.onboarded YES -SUMMON_SCREEN $screen
  sleep 6
  xcrun simctl io "$DEVICE" screenshot iphone-$screen.png
done
```

`-SUMMON_SCREEN` is debug-only, so these have to be Debug builds — which is also why
each launch needs ~20 seconds before the shot. A Release build opens in a quarter of a
second but ignores the argument, because the code is not compiled in. The library has
to be copied into the app container first; see `PhoneHomeView` and `PadRootView` for
where the argument is read.

Suppress the keyboard tutorial first, or it covers half of any screen with a text
field:

```sh
xcrun simctl spawn "$DEVICE" defaults write com.apple.keyboard.preferences \
  DidShowContinuousPathIntroduction -bool YES
```

## The Mac frames

`SUMMON_SNAPSHOT` renders them, but only from a build with Screen Recording permission:
without it macOS substitutes a yellow "restricted" placeholder for anything backed by a
window server surface, and the harness writes that out as happily as it would write the
real thing. The signing change cost the old grant, so `mac-*.png` here are padded from
`docs/screenshots/*.png`, which were rendered while it held. Re-grant Screen Recording
to `dist/Summon.app` to render fresh ones.
