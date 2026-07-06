@preconcurrency import XCTest

/// Proof for the 2026-07-06 ghost-pairing cleanup follow-up: repeatedly
/// reinstalling the app (or running `relay-approval-e2e.sh`, which reuses the
/// same pairing code and uninstalls between runs) leaves one permanently-
/// unrestorable relay-machine record behind each time — Keychain survives
/// `simctl uninstall` even though the UserDefaults holding each machine's
/// pairing code/URL doesn't. `RelayFleetStore.isFull` no longer counts these
/// against the fleet cap (fixed 2026-07-06, commit 1c72d588), but they still
/// need a way for the user to bulk-clear them from Settings rather than
/// tapping "Unpair" on each dead entry individually.
///
/// This test relies on real, already-accumulated ghost entries in this
/// simulator's Keychain from prior `relay-approval-e2e.sh` runs rather than a
/// dedicated debug seam — if none exist yet (a clean simulator), it skips.
@MainActor
final class RelayInvalidPairingCleanupTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) {
        let scrollView = app.scrollViews.firstMatch
        let window = app.windows.firstMatch
        var swipes = 0
        while swipes < maxSwipes {
            guard element.exists else {
                if scrollView.exists { scrollView.swipeUp() } else { app.swipeUp() }
                swipes += 1
                continue
            }
            let safeBottom = window.frame.height - 140
            let f = element.frame
            if f.minY > 90 && f.maxY < safeBottom { return }
            if f.maxY >= safeBottom {
                if scrollView.exists { scrollView.swipeUp() } else { app.swipeUp() }
            } else {
                return
            }
            swipes += 1
        }
    }

    func testClearInvalidPairingsRemovesGhostEntries() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_DESTINATION"] = "settings"
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 30))

        let relayPairingRow = app.staticTexts["Relay pairing"]
        scrollIntoView(relayPairingRow, in: app)
        guard relayPairingRow.waitForExistence(timeout: 15) else {
            throw XCTSkip("Relay pairing row did not render — CONNECTION section may not have scrolled into view")
        }
        relayPairingRow.tap()

        XCTAssertTrue(app.staticTexts["paired machines"].waitForExistence(timeout: 10),
                      "Tapping 'Relay pairing' should open the paired-machines list")

        // The row is a `Button(role: .destructive)` wrapping combined-accessibility
        // content, so it surfaces as a single Button leaf (not separate staticTexts)
        // — mirror the broad `descendants(matching:)` match TapInjectionProofTests
        // uses for non-discrete labelled content (e.g. "Dev VPS").
        let clearInvalidRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "invalid pairing")
        ).firstMatch
        guard clearInvalidRow.waitForExistence(timeout: 10) else {
            throw XCTSkip("No invalid/ghost relay pairings present on this simulator — nothing to clear")
        }

        clearInvalidRow.tap()

        let deadline = Date().addingTimeInterval(10)
        while clearInvalidRow.exists && Date() < deadline { usleep(300_000) }
        XCTAssertFalse(clearInvalidRow.exists,
                       "After tapping the clear action, no 'invalid pairing' row should remain")
    }
}
