import Foundation

/// Pure auto-scroll / jump-to-latest decisions for the Work Thread transcript. No
/// `#if os(iOS)` gate — `CGFloat` is available cross-platform via CoreGraphics/Foundation,
/// so this stays testable via `swift test` on macOS.
///
/// Ported pattern (logic only, see `docs/product/2026-07-09-chat-ui-port-map.md` §8):
/// - Orca (MIT, `src/shared/native-chat-autoscroll.ts:1-44`): pure `isNearBottom` (48pt
///   threshold) / `shouldShowJumpToLatest` geometry decisions; follow the bottom only while
///   the viewport is near it, stop unconditionally-scrolling once the reader detaches.
/// - Happier (MIT, `JumpToBottomButton.tsx`): unread-count badge accrues while detached and
///   clears on re-follow.
public enum CursorTranscriptAutoScrollPolicy {
    /// Orca's near-bottom threshold (native-chat-autoscroll.ts).
    public static let nearBottomThreshold: CGFloat = 48

    public static func isNearBottom(offsetFromBottom: CGFloat) -> Bool {
        offsetFromBottom <= nearBottomThreshold
    }

    public static func shouldShowJumpToLatest(isFollowing: Bool, hasContentBelow: Bool) -> Bool {
        !isFollowing && hasContentBelow
    }

    /// Tracks whether the transcript is "following" the bottom, plus an unread badge count
    /// accrued while detached — the state the view drives from scroll-geometry callbacks.
    public struct FollowState: Equatable, Sendable {
        public var isFollowing: Bool
        public var unreadCount: Int

        public init(isFollowing: Bool = true, unreadCount: Int = 0) {
            self.isFollowing = isFollowing
            self.unreadCount = unreadCount
        }

        /// The reader scrolled; re-evaluate following purely from the new geometry.
        public func handlingScroll(offsetFromBottom: CGFloat) -> FollowState {
            var next = self
            if CursorTranscriptAutoScrollPolicy.isNearBottom(offsetFromBottom: offsetFromBottom) {
                next.isFollowing = true
                next.unreadCount = 0
            } else {
                next.isFollowing = false
            }
            return next
        }

        /// New content landed (a row appended). Only accrue "unread" while detached; while
        /// following, the caller auto-scrolls and there is nothing unread.
        public func handlingNewRow(offsetFromBottom: CGFloat) -> FollowState {
            var next = self
            if next.isFollowing || CursorTranscriptAutoScrollPolicy.isNearBottom(offsetFromBottom: offsetFromBottom) {
                next.isFollowing = true
                next.unreadCount = 0
            } else {
                next.unreadCount += 1
            }
            return next
        }

        /// The reader tapped the jump-to-latest pill: re-engage following and clear unread.
        public func handlingJumpToLatest() -> FollowState {
            FollowState(isFollowing: true, unreadCount: 0)
        }
    }
}
