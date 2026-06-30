# Design-redo findings log

> Running notes captured during the redo that aren't worth fixing the moment we find them — pick
> these up when we reach the relevant screen in the actual Mobbin workflow pass. Not a priority
> list, just a parking lot so nothing gets lost between sessions.

## Inbox (`InboxView.swift` / `InboxApprovalCard.swift`)

- **Redundant "NEEDS YOUR APPROVAL" label.** Appears twice per card: once as the section header
  above the list, once again verbatim as a small badge on every individual card inside that
  section. Once you're scanning a section titled "Needs your approval," repeating it on each card
  adds no information — that vertical space could carry something useful instead (e.g. which
  machine, or a one-line risk reason). Found 2026-07-01 sanity-checking the copy style guide
  against the live Inbox screen.

## Cross-cutting / not screen-specific

- **Two approval-card components disagree on copy.** `InboxApprovalDetail.swift` already does
  `isCritical ? "Authenticate to Approve" : "Approve"` on its primary button. `InboxApprovalCard.swift`
  (the list/inline card) just says "Approve" regardless of risk — the Face ID requirement is a
  separate small text line the button itself doesn't echo. When we redo the approval flow's copy,
  make `InboxApprovalCard` match the pattern `InboxApprovalDetail` already proved out, not invent a
  third treatment.
