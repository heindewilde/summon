# App Store screenshots

Captured from the simulator against the demo library — no real data, which is also why
the numbers in them are an example IBAN rather than anyone's.

**Look at every frame before uploading.** The first set went to the App Store showing
nothing but a loading spinner: a Debug build on a cold simulator takes longer to open
its library than the capture waited, and a screenshot of a spinner looks exactly like a
screenshot until someone opens it. `asc.py screenshots` cannot tell the difference.

- `iphone-*.png` — iPhone 17 Pro (6.9"), dark
- `ipad-home.png` — iPad Pro 13", dark
- `mac-1-panel-dark.png`, `mac-2-library-dark.png` — Mac, 2880 × 1800: a real window from
  the live-capture harness, grabbed with `screencapture -l` and centred on a dark canvas.
  See "The Mac frames" below.

Re-capture after a UI change:

```sh
# The demo library the shots use
Scripts/selftest.sh

DEVICE=<simulator udid>
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --wifiBars 3
for screen in home detail settings; do
  xcrun simctl terminate "$DEVICE" com.heindewilde.summon
  xcrun simctl launch "$DEVICE" com.heindewilde.summon -app.onboarded YES -SUMMON_SCREEN $screen
  sleep 6
  xcrun simctl io "$DEVICE" screenshot iphone-$screen.png  # then number them: the store shows them in name order
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

`SUMMON_LIVE` opens the real view in a real window without taking focus, and writes
that window's number to `SUMMON_LIVE_INFO`, so `screencapture -l` grabs exactly it.
The capturing process (the terminal) needs Screen Recording; the app does not. The
panel goes on the sharpest screen, not the pointer's, so the frame is never 1x.

```sh
INFO="$HOME/Library/Containers/com.heindewilde.summon/Data/tmp/live.txt"
SUMMON_DEMO=1 SUMMON_APPEARANCE=dark SUMMON_LIVE=panel SUMMON_LIVE_QUERY=invoice \
  SUMMON_LIVE_INFO="$INFO" dist/Summon.app/Contents/MacOS/Summon &
sleep 6; screencapture -x -l"$(cat "$INFO")" panel.png; kill %1
# SUMMON_LIVE=library SUMMON_LIVE_KIND=document for the library window
```

The iPhone and iPad apps do not seed a starter library, so copy the Mac demo library
(`~/Library/Group Containers/JV4MVRB77Q.group.com.heindewilde.summon/Summon-Demo`)
into the simulator's app group as `Summon` before capturing them.
