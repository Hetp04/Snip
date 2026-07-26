import SwiftUI

struct ChainView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let onItemCopy: (ClipboardItem) -> Void
    let onCreateChain: () -> Void
    let onEditChain: (Chain) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            chainListView
        }
        .background(Theme.bg)
    }
    
    // MARK: - State A: List View
    
    private var chainListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chains")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: onCreateChain) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Create Chain")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            Divider().background(Theme.divider)
            
            if viewModel.chains.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 80)
                    Image(systemName: "link")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.textTertiary)
                    Text("No chains yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                    Text("Group snippets to paste them in sequence.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(viewModel.chains) { chain in
                            ChainCardView(
                                chain: chain,
                                itemCount: viewModel.chainItems[chain.id]?.count ?? 0,
                                contentIcons: {
                                    let snippets = viewModel.activeItems(for: chain)
                                    var seen = Set<ContentCategory>()
                                    var ordered = [ContentCategory]()
                                    for snippet in snippets {
                                        let category = ContentCategory.detect(from: snippet)
                                        if !seen.contains(category) {
                                            seen.insert(category)
                                            ordered.append(category)
                                        }
                                    }
                                    return ordered
                                }(),
                                onOpen: {
                                    onEditChain(chain)
                                },
                                onPaste: {
                                    viewModel.pasteChain(chain)
                                },
                                onDelete: {
                                    withAnimation {
                                        viewModel.deleteChain(chain)
                                    }
                                }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
    
    // Removed detailView in favor of using ChainNamingOverlay in ContentView
}

// MARK: - ChainCardView

struct ChainCardView: View {
    let chain: Chain
    let itemCount: Int
    let contentIcons: [ContentCategory]
    let onOpen: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chain.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    
                    Text("\(itemCount) snippets")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                
                Spacer(minLength: 12)
                
                HStack(spacing: 8) {
                    if isHovered {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.red.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: onPaste) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isHovered ? Theme.accent : Theme.textTertiary.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .background(isHovered ? Theme.accent.opacity(0.1) : Color.clear)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
                
                if !contentIcons.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(contentIcons.prefix(4).enumerated()), id: \.offset) { _, category in
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(category.iconBackground)
                                    .softInnerShadow(RoundedRectangle(cornerRadius: 6), darkShadow: Color.black.opacity(0.3), lightShadow: Color.white, spread: 0.05, radius: 1)
                                    .frame(width: 24, height: 24)
                                Image(systemName: category.iconName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(category.iconForeground)
                            }
                        }
                        if contentIcons.count > 4 {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.neoBase)
                                    .softInnerShadow(RoundedRectangle(cornerRadius: 6), darkShadow: Color.black.opacity(0.3), lightShadow: Color.white, spread: 0.05, radius: 1)
                                    .frame(width: 24, height: 24)
                                Text("+\(contentIcons.count - 4)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
        }
        .padding(12)
        .background(Theme.neoBase)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .softInnerShadow(RoundedRectangle(cornerRadius: 16), darkShadow: Color.black.opacity(0.3), lightShadow: Color.white, spread: 0.05, radius: isHovered ? 2 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
    }
}


