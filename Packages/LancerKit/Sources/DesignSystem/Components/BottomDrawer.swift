#if os(iOS)
import SwiftUI

/// Legacy alias — `CursorDrawer` is the canonical sheet wrapper.
public typealias LancerDrawer = CursorDrawer

public enum LancerDrawerSurface: Sendable {
    case standard
    case workspace
}

public struct BottomDrawerSheet<DrawerContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String?
    let subtitle: String?
    let detents: Set<PresentationDetent>
    let drawerContent: () -> DrawerContent

    public init(
        isPresented: Binding<Bool>,
        title: String? = nil,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        surface: LancerDrawerSurface = .standard,
        @ViewBuilder content: @escaping () -> DrawerContent
    ) {
        self._isPresented = isPresented
        self.title = title
        self.subtitle = subtitle
        self.detents = detents
        self.drawerContent = content
    }

    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                CursorDrawer(title: title, subtitle: subtitle, detents: detents, content: drawerContent)
            }
    }
}

public extension View {
    func bottomDrawer<C: View>(
        isPresented: Binding<Bool>,
        title: String? = nil,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        surface: LancerDrawerSurface = .standard,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        modifier(
            BottomDrawerSheet(
                isPresented: isPresented,
                title: title,
                subtitle: subtitle,
                detents: detents,
                content: content
            )
        )
    }
}
#endif
