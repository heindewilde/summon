import SummonKit
import SwiftUI

/// Choose a folder's symbol and colour.
///
/// Opened by clicking the folder's icon — the thing you want to change is the thing
/// you click, which is one step rather than two through a context menu.
///
/// The list is a curated hundred rather than all of SF Symbols: a picker returning
/// six thousand results is a worse tool than one returning the right twelve. Search
/// matches meaning as well as name, so "money" finds the currency symbols.
public struct FolderIconPicker: View {
    @Bindable var model: AppModel
    let folder: SummonFolder
    @Binding var isPresented: Bool

    @State private var query: String
    @State private var symbol: String
    @State private var colour: String
    @FocusState private var searchFocused: Bool

    public init(model: AppModel, folder: SummonFolder, isPresented: Binding<Bool>,
                initialQuery: String = "") {
        self.model = model
        self.folder = folder
        _isPresented = isPresented
        _symbol = State(initialValue: folder.symbolName)
        _colour = State(initialValue: folder.colorName)
        _query = State(initialValue: initialQuery)
    }

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: Theme.Space.xs), count: 8)

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A bare TextField with a placeholder reads as a window title, not
            // something you can type into — which is exactly how it was missed. The
            // magnifier and the inset well are what say "this is a field".
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                    .accessibilityHidden(true)

                TextField("Search icons", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.title)
                    .focused($searchFocused)
                    .accessibilityLabel("Search icons")

                if !query.isEmpty {
                    Button {
                        query = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(height: 26)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .padding(Theme.Space.s)

            Divider().overlay(Theme.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.s, pinnedViews: []) {
                    if query.isEmpty {
                        ForEach(FolderIcon.groups) { group in
                            section(group.title, group.symbols)
                        }
                    } else {
                        let results = FolderIcon.search(query)
                        if results.isEmpty {
                            Text("Nothing matches “\(query)”. Try what it is for — money,\npeople, code, travel.")
                                .font(Theme.Typography.meta)
                                .foregroundStyle(Theme.tertiaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Theme.Space.m)
                                .padding(.vertical, Theme.Space.s)
                        } else {
                            section("\(results.count) result\(results.count == 1 ? "" : "s")", results)
                        }
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .frame(height: 240)

            Divider().overlay(Theme.hairline)
            colourRow
        }
        .frame(width: 288)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private func section(_ title: String?, _ symbols: [FolderIcon.Symbol]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let title {
                Text(title.uppercased())
                    .font(Theme.Typography.section)
                    .foregroundStyle(Theme.tertiaryText)
                    .tracking(0.5)
                    .padding(.horizontal, Theme.Space.m)
            }
            LazyVGrid(columns: columns, spacing: Theme.Space.xs) {
                ForEach(symbols) { entry in
                    Button {
                        symbol = entry.name
                        apply()
                    } label: {
                        Image(systemName: entry.name)
                            .font(.system(size: 14))
                            .foregroundStyle(entry.name == symbol
                                             ? Theme.folderColor(colour) : Theme.secondaryText)
                            .frame(width: 30, height: 26)
                            .background {
                                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                    .fill(entry.name == symbol ? Theme.selection : .clear)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(entry.name)
                    .accessibilityLabel(entry.name.replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(entry.name == symbol ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, Theme.Space.m)
        }
    }

    private var colourRow: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(Theme.folderColorNames, id: \.self) { name in
                Button {
                    colour = name
                    apply()
                } label: {
                    Circle()
                        .fill(Theme.folderColor(name))
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle()
                                .strokeBorder(Theme.primaryText, lineWidth: name == colour ? 2 : 0)
                                .padding(-3)
                        }
                }
                .buttonStyle(.plain)
                .help(name.capitalized)
                .accessibilityLabel(name)
                .accessibilityAddTraits(name == colour ? [.isSelected, .isButton] : .isButton)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 40)
    }

    private func apply() {
        model.store.setFolderIcon(folder, symbolName: symbol, colorName: colour)
    }
}
