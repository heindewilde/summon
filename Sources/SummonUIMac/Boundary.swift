/// The macOS half of the view layer.
///
/// The same boundary `SummonKitMac` draws, one layer up. The panel is an
/// `NSPanel` that deliberately never becomes main; the menu bar is a
/// `MenuBarExtra`; the search field is an `NSTextField` so the arrow keys can drive
/// the list; the hot key recorder reads `NSEvent`. Those are macOS surfaces, not
/// unported ones.
///
/// What stays behind in `SummonUI` is the part that was always portable and could
/// not prove it: `Theme` and the whole design system, the row every surface draws,
/// the controls, and `AppModel`.
public enum SummonUIMac {}
