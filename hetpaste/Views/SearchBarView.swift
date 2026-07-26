import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Search...", text: $text)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Theme.textPrimary)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.textTertiary.opacity(0.8))
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(hex: "#F6F6F6"))
                .softInnerShadow(
                    Capsule(),
                    darkShadow: Color.black.opacity(isFocused ? 0.35 : 0.22),
                    lightShadow: Color.white,
                    spread: 0.05,
                    radius: isFocused ? 4 : 3
                )
        )
    }
}