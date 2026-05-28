import SwiftUI

// Reusable bottom-drawer container with keyboard-style slide animation.
// Uses cubic-bezier(0.2, 0, 0, 1) ≈ SwiftUI .spring(response:0.38, dampingFraction:0.86)
// Presented via sheet with .presentationDetents for native iOS drag behaviour.
// Callers use .bottomDrawer(isPresented:) for a sheet-based presentation, or
// embed BottomDrawerContent directly for inline use.

// MARK: - Sheet modifier (preferred for Diff + File preview)

public struct BottomDrawerSheet<DrawerContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let detents: Set<PresentationDetent>
    let drawerContent: () -> DrawerContent

    public init(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> DrawerContent
    ) {
        self._isPresented = isPresented
        self.detents = detents
        self.drawerContent = content
    }

    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                DrawerShell(detents: detents, content: drawerContent)
            }
    }
}

// MARK: - Drawer shell (the actual drawer UI)

struct DrawerShell<Content: View>: View {
    let detents: Set<PresentationDetent>
    let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    var body: some View {
        NavigationStack {
            content()
                .background(t.surf1)
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(t.surf1)
    }
}

// MARK: - View extension

public extension View {
    func bottomDrawer<C: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        modifier(BottomDrawerSheet(isPresented: isPresented, detents: detents, content: content))
    }
}

// MARK: - Standalone inline drawer (for overlay within parent views)

public struct InlineBottomDrawer<Content: View>: View {
    @Binding var isPresented: Bool
    let content: () -> Content

    @Environment(\.conduitTokens) private var t
    @State private var dragOffset: CGFloat = 0

    public init(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self._isPresented = isPresented
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                // Dimmed scrim
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)

                // Drawer card
                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(t.surf3)
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    content()
                }
                .background(t.surf1)
                .clipShape(RoundedRectangle(cornerRadius: t.radiusXL, style: .continuous))
                .offset(y: max(0, dragOffset))
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = $0.translation.height }
                        .onEnded { if $0.translation.height > 80 { dismiss() } else {
                            withAnimation(drawerSpring) { dragOffset = 0 }
                        }}
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(drawerSpring, value: isPresented)
    }

    private func dismiss() {
        withAnimation(drawerSpring) { isPresented = false }
    }

    // keyboard-slide spring: response=0.38s, damping≈0.86 ≈ cubic-bezier(0.2,0,0,1)
    private let drawerSpring = Animation.spring(response: 0.38, dampingFraction: 0.86)
}
