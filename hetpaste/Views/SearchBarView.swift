import SwiftUI
import AppKit

struct SearchBarView: View {
    @Binding var query: ClipboardSearchQuery
    @Binding var shouldFocus: Bool
    @Binding var showsAdvanced: Bool
    let items: [ClipboardItem]
    let folders: [ClipboardFolder]
    @FocusState private var isFocused: Bool
    @State private var highlightedIndex = 0
    @State private var selectedTokenID: String?
    @State private var hoveredTokenID: String?
    @State private var backspaceMonitor: Any?

    private var suggestions: [SearchSuggestion] {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // One-character input is too ambiguous to be useful. Waiting for a
        // second character prevents the menu from becoming a noisy catalog.
        guard isFocused, needle.count >= 2 else { return [] }
        let appGroups = Dictionary(grouping: items, by: \ClipboardItem.sourceAppName)
        var candidates: [ClipboardSearchToken] = [
            .category(.text), .category(.url), .category(.image), .category(.file),
            .category(.code), .category(.color), .category(.email), .category(.phone),
            .category(.richText), .category(.video)
        ]
        candidates += ClipboardDateFilter.allCases.map(ClipboardSearchToken.date)
        candidates += ClipboardStatusFilter.allCases.map(ClipboardSearchToken.status)
        candidates += appGroups.map { name, values in .sourceApp(name: name, bundleID: values.compactMap(\.sourceAppBundleID).first) }
        candidates += folders.map { .folder(id: $0.id, name: $0.name) }
        return candidates.filter { candidate in !query.tokens.contains(where: { $0.id == candidate.id }) }.compactMap { candidate in
            let label = candidate.label.lowercased(), category = candidate.category.lowercased()
            let base: Int
            if label == needle { base = 1_000 }
            else if label.hasPrefix(needle) { base = 800 - label.count }
            else if label.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { base = 650 - label.count }
            else if needle.count >= 3 && (label.contains(needle) || category.hasPrefix(needle)) { base = 450 - label.count }
            else if needle.count >= 4 && Self.isSubsequence(needle, of: label) { base = 200 - label.count }
            else { return nil }
            return SearchSuggestion(token: candidate, score: base + (candidate.category == "App" ? min(appGroups[candidate.label]?.count ?? 0, 99) : 0))
        }.sorted { $0.score == $1.score ? $0.token.label < $1.token.label : $0.score > $1.score }.prefix(5).map { $0 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundColor(Theme.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(query.tokens) { token in tokenView(token) }
                        TextField(query.tokens.isEmpty ? "Search..." : "Add filter or search…", text: $query.text)
                            .focused($isFocused).textFieldStyle(.plain).font(.system(size: 13))
                            .frame(minWidth: query.tokens.isEmpty ? 180 : 130)
                            .onKeyPress(.downArrow) { moveHighlight(1); return .handled }
                            .onKeyPress(.upArrow) { moveHighlight(-1); return .handled }
                            .onKeyPress(.return) { applyHighlighted() ? .handled : .ignored }
                            .onKeyPress(.tab) { applyHighlighted() ? .handled : .ignored }
                            .onKeyPress(.escape) { query.text = ""; selectedTokenID = nil; return .handled }
                            .onChange(of: query.text) { _, _ in highlightedIndex = 0; selectedTokenID = nil }
                    }
                }
                if query.isActive {
                    Button { query = ClipboardSearchQuery(); selectedTokenID = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundColor(Theme.textSecondary)
                    }.buttonStyle(.plain).help("Clear search")
                }
                Button { withAnimation(.easeOut(duration: 0.16)) { showsAdvanced.toggle() } } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(showsAdvanced ? Theme.accent : Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(showsAdvanced ? Theme.accent.opacity(0.10) : Color.clear))
                }
                .buttonStyle(.plain)
                .help("Advanced filters")
            }
            .padding(.horizontal, 16).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#F6F6F6")))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isFocused ? Theme.textTertiary.opacity(0.35) : Theme.border.opacity(0.7), lineWidth: 1))
            if !suggestions.isEmpty {
                suggestionMenu
                    .padding(.top, 51)
                    // Suggestions should feel anchored to the field. Moving
                    // the whole popup on each keystroke reads as visual jitter.
                    .transition(.identity)
            }
        }
        .frame(height: 46, alignment: .top)
        .zIndex(30)
        .onChange(of: shouldFocus) { _, value in guard value else { return }; isFocused = true; shouldFocus = false }
        .onAppear { installBackspaceMonitor() }
        .onDisappear { removeBackspaceMonitor() }
    }

    private var suggestionMenu: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button { apply(suggestion.token) } label: {
                    HStack(spacing: 9) {
                        tokenIcon(suggestion.token, size: 16)
                        Text(suggestion.token.label).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textPrimary)
                        Spacer()
                        if suggestion.token.category != "Date" {
                            Text(suggestion.token.category).font(.system(size: 10)).foregroundColor(Theme.textTertiary)
                        }
                    }.padding(.horizontal, 10).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(index == highlightedIndex ? Color.black.opacity(0.055) : Color.clear))
                }.buttonStyle(.plain).onHover { if $0 { highlightedIndex = index } }
            }
        }.padding(5).frame(width: 270)
            .background(RoundedRectangle(cornerRadius: 13).fill(Theme.card).shadow(color: .black.opacity(0.12), radius: 12, y: 5))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border.opacity(0.8), lineWidth: 0.75)).zIndex(20)
    }


    private func tokenView(_ token: ClipboardSearchToken) -> some View {
        HStack(spacing: 5) {
            tokenIcon(token, size: 13)
            Text(token.label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            if hoveredTokenID == token.id {
                Button { remove(token) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
            }
        }.foregroundColor(Theme.textSecondary).padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(selectedTokenID == token.id ? 0.1 : 0.055)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedTokenID == token.id ? Theme.textSecondary.opacity(0.45) : Color.clear))
            .contentShape(Rectangle()).onTapGesture { selectedTokenID = token.id; isFocused = true }
            .onHover { hoveredTokenID = $0 ? token.id : nil }
    }

    @ViewBuilder private func tokenIcon(_ token: ClipboardSearchToken, size: CGFloat) -> some View {
        if let bundleID = token.bundleID, let icon = IconCache.shared.resolveAppIcon(bundleID: bundleID) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else { Image(systemName: token.icon).font(.system(size: size - 2, weight: .medium)).frame(width: size, height: size) }
    }
    private func apply(_ token: ClipboardSearchToken) {
        // A click changes both the token list and input text. Apply them in one
        // transaction so the chip does not animate through an intermediate
        // layout, then restore the AppKit text field's first responder status.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            query.tokens.append(token)
            query.text = ""
            selectedTokenID = nil
            highlightedIndex = 0
        }
        DispatchQueue.main.async { isFocused = true }
    }
    private func remove(_ token: ClipboardSearchToken) { query.tokens.removeAll { $0.id == token.id }; selectedTokenID = nil; isFocused = true }
    private func applyHighlighted() -> Bool { guard suggestions.indices.contains(highlightedIndex) else { return false }; apply(suggestions[highlightedIndex].token); return true }
    private func moveHighlight(_ amount: Int) { guard !suggestions.isEmpty else { return }; highlightedIndex = (highlightedIndex + amount + suggestions.count) % suggestions.count }
    private func installBackspaceMonitor() {
        guard backspaceMonitor == nil else { return }
        backspaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 51, // macOS Backspace/Delete key
                  isFocused,
                  query.text.isEmpty,
                  let last = query.tokens.last else { return event }
            remove(last)
            return nil
        }
    }
    private func removeBackspaceMonitor() {
        if let backspaceMonitor { NSEvent.removeMonitor(backspaceMonitor) }
        backspaceMonitor = nil
    }
    private static func isSubsequence(_ needle: String, of value: String) -> Bool {
        var iterator = value.makeIterator()
        return needle.allSatisfy { character in while let next = iterator.next() { if next == character { return true } }; return false }
    }
}
