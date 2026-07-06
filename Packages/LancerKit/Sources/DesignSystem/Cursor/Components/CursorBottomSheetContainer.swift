#if os(iOS)
import SwiftUI

/// A shape that rounds only the specified corners, used so bottom sheets round
/// their top corners only (bottom stays flush with the screen edge).
public struct RoundedCorner: Shape {
    public struct Corners: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let topLeft = Corners(rawValue: 1 << 0)
        public static let topRight = Corners(rawValue: 1 << 1)
        public static let bottomLeft = Corners(rawValue: 1 << 2)
        public static let bottomRight = Corners(rawValue: 1 << 3)
        public static let top: Corners = [.topLeft, .topRight]
        public static let all: Corners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    private let radius: CGFloat
    private let corners: Corners

    public init(radius: CGFloat, corners: Corners) {
        self.radius = radius
        self.corners = corners
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            radius: tr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(
            center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
            radius: bl,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(
            center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
            radius: tl,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Bottom sheet chrome shared by Run-on / Model pickers and the expanded
/// composer: a drag handle, a header row with an optional leading circular
/// button and a centered title, and arbitrary content below. Top corners only
/// are rounded — the bottom stays flush with the screen edge.
public struct CursorBottomSheetContainer<Content: View>: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let title: String
    private let leadingButton: (systemImageName: String, action: () -> Void)?
    private let content: () -> Content

    public init(
        title: String,
        leadingButton: (systemImageName: String, action: () -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.leadingButton = leadingButton
        self.content = content
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(spacing: 0) {
            Capsule()
                .fill(colors.mutedText)
                .frame(width: CursorMetrics.sheetDragHandleWidth, height: CursorMetrics.sheetDragHandleHeight)
                .padding(.top, CursorMetrics.sheetDragHandleTopPadding)
                .padding(.bottom, CursorMetrics.sheetDragHandleBottomPadding)

            ZStack {
                Text(title)
                    .font(CursorType.sheetTitle)
                    .foregroundColor(colors.primaryText)

                HStack {
                    if let leadingButton {
                        CursorIconButton(
                            systemImageName: leadingButton.systemImageName,
                            diameter: CursorMetrics.sheetLeadingButtonDiameter,
                            action: leadingButton.action
                        )
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
            .padding(.bottom, CursorMetrics.sheetHeaderBottomPadding)

            content()
        }
        .background(colors.sheetBackground)
        .clipShape(RoundedCorner(radius: CursorMetrics.sheetTopCornerRadius, corners: .top))
    }
}
#endif
