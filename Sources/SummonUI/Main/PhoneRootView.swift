#if !canImport(AppKit)
import SummonKit
import SwiftUI

/// The library on a phone.
///
/// A `NavigationSplitView` is right for a window that can show three columns at once
/// and wrong for a screen that can show one: on iPhone it collapses to the sidebar and
/// then has nowhere to go, because choosing a section only sets state and a window
/// would already be showing the result.
///
/// So the same three views, pushed rather than placed side by side. iPad keeps the
/// split view, which is what `MainWindowView` already is.
public struct PhoneRootView: View {
    @Bindable var model: AppModel
    @State private var path: [Route] = []

    public init(model: AppModel) { self.model = model }

    enum Route: Hashable {
        case list
        case item(UUID)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            SidebarView(model: model) { _ in
                path.append(.list)
            }
            // The same ground the library window draws. Without it the phone falls
            // back to the system's plain white, which is the exact thing the note on
            // GlassBackground says went wrong on the Mac: every surface got the ground
            // except the one people spend the most time in.
            .background(GlassBackground(material: .sidebar, bloom: 1.1))
            .navigationTitle("Summon")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .list:
                    ItemListView(model: model, items: model.itemsForSidebar())
                        .background(GlassBackground(material: .underWindowBackground, bloom: 0.35))
                        .navigationTitle(model.sidebarTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .searchable(text: $model.mainSearch, prompt: "Search this view")
                        .onChange(of: model.mainSelection) { _, new in
                            guard let new else { return }
                            path.append(.item(new))
                        }
                case .item(let id):
                    ItemDetailView(model: model, itemID: id)
                        .background(GlassBackground(material: .underWindowBackground, bloom: 0.5))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .padding(.bottom, Theme.Space.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Theme.panelIn, value: model.toast)
        }
        // Popping back to the list must clear the selection, or choosing the same item
        // again pushes nothing — `onChange` never fires for a value that did not change.
        .onChange(of: path) { _, new in
            if !new.contains(where: { if case .item = $0 { return true } else { return false } }) {
                model.mainSelection = nil
            }
        }
    }
}
#endif
