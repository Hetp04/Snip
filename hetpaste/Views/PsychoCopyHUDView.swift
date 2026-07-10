import SwiftUI
struct PsychoCopyHUDView: View {
    @ObservedObject var manager: PsychoCopyManager
    @State private var draggingItemID: UUID? = nil
    @State private var dragOffset: CGFloat = 0      
    @State private var insertionTarget: Int? = nil  
    private let rowHeight: CGFloat = 41
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                if manager.isHUDExpanded && !manager.copyQueue.isEmpty {
                    expandedQueueView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                pillView
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.clear)
    }
    private var pillView: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.copyQueue.isEmpty
                  ? "square.stack.3d.up"
                  : "square.stack.3d.up.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.accent)
                .symbolEffect(.bounce, value: manager.copyQueue.count)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sequential Paste")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                let count = manager.copyQueue.count
                Text(count == 0 ? "Queue empty" : "\(count) item\(count == 1 ? "" : "s") queued")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            if let latestItem = manager.copyQueue.items.last {
                Divider()
                    .frame(height: 20)
                    .overlay(Color.white.opacity(0.2))
                Text(previewText(for: latestItem))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 80, maxWidth: 260, alignment: .leading)
                    .id(latestItem.id)
            }
            Spacer(minLength: 8)
            if !manager.copyQueue.isEmpty {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .rotationEffect(.degrees(manager.isHUDExpanded ? 0 : 180))
                    .animation(.easeInOut(duration: 0.2), value: manager.isHUDExpanded)
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            manager.isHUDExpanded.toggle()
                        }
                    }
            }
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.4))
                .contentShape(Circle())
                  .onTapGesture {
                    manager.deactivateMultiCopyMode()
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 6)
    }
    @ViewBuilder
    private var expandedQueueView: some View {
        VStack(spacing: 0) {
            ForEach(Array(manager.copyQueue.items.enumerated()), id: \.element.id) { index, item in
                let isDragging = draggingItemID == item.id
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(isDragging ? 0.7 : 0.25))
                            .frame(width: 16)
                        Text("\(isDragging ? (insertionTarget ?? index) + 1 : index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(isDragging ? Theme.accent.opacity(0.75) : Theme.accent))
                            .animation(.easeInOut(duration: 0.12), value: insertionTarget)
                        Text(previewText(for: item))
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(isDragging ? 1.0 : 0.85))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                    if index < manager.copyQueue.items.count - 1 {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
                .scaleEffect(isDragging ? 1.03 : 1.0, anchor: .center)
                .shadow(color: isDragging ? Color.black.opacity(0.5) : .clear, radius: 10, y: 4)
                .zIndex(isDragging ? 1 : 0)
                .offset(y: rowOffset(for: index))
                .animation(isDragging ? .none : .easeInOut(duration: 0.14), value: insertionTarget)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if draggingItemID == nil {
                                draggingItemID = item.id
                                insertionTarget = index
                            }
                            guard draggingItemID == item.id else { return }
                            dragOffset = value.translation.height
                            let count = manager.copyQueue.items.count
                            let steps = Int((dragOffset / rowHeight).rounded())
                            let newTarget = max(0, min(count - 1, index + steps))
                            if newTarget != insertionTarget {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    insertionTarget = newTarget
                                }
                            }
                        }
                        .onEnded { _ in
                            let items = manager.copyQueue.items
                            guard let draggedID = draggingItemID,
                                  let fromIndex = items.firstIndex(where: { $0.id == draggedID })
                            else {
                                draggingItemID = nil; dragOffset = 0; insertionTarget = nil
                                return
                            }
                            let toIndex = insertionTarget ?? fromIndex
                            let count = items.count
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                draggingItemID = nil
                                dragOffset = 0
                                insertionTarget = nil
                                if fromIndex != toIndex {
                                    manager.moveItems(
                                        from: IndexSet(integer: fromIndex),
                                        to: toIndex > fromIndex ? min(toIndex + 1, count) : toIndex
                                    )
                                }
                            }
                        }
                )
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
    }
    private func rowOffset(for index: Int) -> CGFloat {
        guard let draggedID = draggingItemID,
              let draggingIdx = manager.copyQueue.items.firstIndex(where: { $0.id == draggedID })
        else { return 0 }
        if index == draggingIdx { return dragOffset }
        guard let target = insertionTarget else { return 0 }
        if draggingIdx < target {
            if index > draggingIdx && index <= target { return -rowHeight }
        } else if draggingIdx > target {
            if index >= target && index < draggingIdx { return rowHeight }
        }
        return 0
    }
    private func previewText(for item: ClipboardItem) -> String {
        switch item.contentType {
        case .text, .richText, .url:
            return (item.contentText ?? "").replacingOccurrences(of: "\n", with: " ")
        case .image: return "[Image]"
        case .video: return "[Video]"
        case .file:  return "[File]"
        }
    }
}