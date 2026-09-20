# App Store screenshots

Captured from the simulator against the demo library — no real data, which is also why
the numbers in them are an example IBAN rather than anyone's.

- `iphone-*.png` — iPhone 17 Pro (6.9"), dark
- `ipad-home.png` — iPad Pro 13", dark

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

`-SUMMON_SCREEN` is debug-only; a shipping build ignores it because the code is not
compiled in. The library has to be copied into the app container first — see
`PhoneHomeView` for where the argument is read.
