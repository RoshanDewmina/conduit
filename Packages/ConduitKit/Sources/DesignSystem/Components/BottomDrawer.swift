import SwiftUI

public enum ConduitDrawerSurface: Sendable {
    case standard
    case workspace
}

public struct ConduitDrawer<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let detents: Set<PresentationDetent>
    private let surface: ConduitDrawerSurface
    private let content: Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        surface: ConduitDrawerSurface = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detents = detents
        self.surface = surface
        self.content = content()
    }

    private var tokens: ConduitTokens { surface == .workspace ? .dark : t }

    public var body: some View {
        VStack(spacing: 0) {
            ConduitGrabHandle(on: surface == .workspace ? .dark : .light)
            if let title {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.dsDisplayPt(24, weight: .bold))
                            .foregroundStyle(tokens.text)
                        if let subtitle {
                            Text(subtitle)
                                .font(.dsSansPt(13))
                                .foregroundStyle(tokens.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    DSCircleButton("xmark", accessibilityLabel: "Dismiss", action: dismiss.callAsFunction)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(tokens.bg)
        .environment(\.conduitTokens, tokens)
        .preferredColorScheme(surface == .workspace ? .dark : nil)
        .presentationDetents(detents)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(surface == .workspace ? 26 : 30)
        .presentationBackground(tokens.bg)
    }
}

public struct BottomDrawerSheet<DrawerContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String?
    let subtitle: String?
    let detents: Set<PresentationDetent>
    let surface: ConduitDrawerSurface
    let drawerContent: () -> DrawerContent

    public init(
        isPresented: Binding<Bool>,
        title: String? = nil,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        surface: ConduitDrawerSurface = .standard,
        @ViewBuilder content: @escaping () -> DrawerContent
    ) {
        self._isPresented = isPresented
        self.title = title
        self.subtitle = subtitle
        self.detents = detents
        self.surface = surface
        self.drawerContent = content
    }

    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                ConduitDrawer(
                    title: title,
                    subtitle: subtitle,
                    detents: detents,
                    surface: surface,
                    content: drawerContent
                )
            }
    }
}

public extension View {
    func bottomDrawer<C: View>(
        isPresented: Binding<Bool>,
        title: String? = nil,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        surface: ConduitDrawerSurface = .standard,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        modifier(
            BottomDrawerSheet(
                isPresented: isPresented,
                title: title,
                subtitle: subtitle,
                detents: detents,
                surface: surface,
                content: content
            )
        )
    }
}
