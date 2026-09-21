import SummonHarness
import SummonMacApp

// The development launcher: the app plus its runtime harnesses. `Scripts/build-app.sh`
// and `Scripts/selftest.sh` build this. The App Store build is `Apps/SummonMac`,
// which launches the same app without linking the harness.
MainActor.assumeIsolated {
    HarnessLauncher.install()
}
SummonApp.main()
