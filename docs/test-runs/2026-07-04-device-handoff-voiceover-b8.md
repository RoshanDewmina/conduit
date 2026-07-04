# B8 remainder — VoiceOver + Dynamic Type device pass

Date: 2026-07-04  
Branch: `cursor/voiceover-b8-remainder-9257`  
Surfaces: Fleet detail, Governance (Policy/Audit), Settings remainder

## Setup

- [ ] Install build from branch
- [ ] Settings → Accessibility → VoiceOver **On**
- [ ] Optional second pass: Dynamic Type → Accessibility XL

## Screens to swipe through

| Screen | VoiceOver: logical reading order? | No duplicate status dots? | Tappable children still work? | Dynamic Type XL OK? | Pass/Fail |
|--------|-----------------------------------|---------------------------|-------------------------------|---------------------|-----------|
| Fleet detail | | | | | |
| Policy home | | | | | |
| Policy editor | | | | | |
| Policy presets | | | | | |
| Audit log | | | | | |
| Settings root | | | | | |
| Relay machines | | | | | |
| Secrets | | | | | |
| SSH keys | | | | | |
| Doctor | | | | | |
| Sync status | | | | | |

## Known fixes in branch (code review)

- `.accessibilityElement(children: .combine)` on read-only groups
- `.contain` where Refresh/Delete/etc. must stay independent
- `.dsSansPt` / `.dsMonoPt` replacing hardcoded system sizes
- Per-caller labels on `DSStatusDot`-style indicators

Owner sign-off: _______________
