import SwiftUI
struct OptionalScrollModifier: ViewModifier {
    let isScrollable: Bool
    func body(content: Content) -> some View {
        if isScrollable {
            ScrollView {
                content
            }
        } else {
            content
        }
    }
}