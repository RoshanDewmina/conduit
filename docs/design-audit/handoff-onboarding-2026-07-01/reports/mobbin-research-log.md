# Mobbin Research Log

Updated: 2026-06-30

This file records the Mobbin examples reviewed during the Lancer UI/UX polish pass. Use it as the source list for designer review. Third-party screenshots are not copied into the repo; each reference links back to its canonical Mobbin screen or flow.

## Onboarding / Pairing

| Reference | Why it matters for Lancer | Adapt | Avoid |
| --- | --- | --- | --- |
| [Granola welcome](https://mobbin.com/screens/5de8fd45-4580-4191-8cbd-0008a01b8b1e) | Strong first-run framing with product-specific confidence. | One clear promise and a concrete product preview. | Do not copy the meeting-notes tone. |
| [ClickUp onboarding/product screen](https://mobbin.com/screens/d0deaf53-deda-4b3d-8c8a-414f706c3ff0) | Shows how a productivity app introduces value before asking for setup. | Keep first-run copy short and action-oriented. | Do not import project-management language. |
| [Craft onboarding/product screen](https://mobbin.com/screens/56750e8c-724a-4cdf-bf6f-0ab01384739f) | Uses polished product framing for a creation tool. | Use product imagery as proof. | Do not make Lancer feel like a document app. |
| [Tesla setup/product screen](https://mobbin.com/screens/1e568ba7-a457-4c32-b6d4-1a0b4cc9a211) | Makes device/product connection feel tangible. | Tie setup to the real controlled object: the user's machine. | Do not copy consumer hardware glamour. |
| [Coupang Play connecting a new device](https://mobbin.com/flows/a7566550-fd7f-429b-92a3-9f2b754b7f42) | Multi-step device connection with verification. | Pairing needs visible progress and confirmation. | Do not use streaming-TV language. |
| [Xbox setting up a console](https://mobbin.com/flows/8409dc9b-c0dd-415c-9f5b-8a9b2095d505) | Device setup breaks a complex connection into understandable steps. | Use step clarity for code verification and connection health. | Do not add unnecessary setup steps. |
| [WhatsApp linking a device](https://mobbin.com/flows/dd21cacc-071a-4f4a-8813-ecf59e796ac7) | Trusted-device linking is clear and familiar. | Frame code entry as linking this phone to a machine. | Do not copy QR-first mechanics in V1. |
| [Meta Quest pairing a headset](https://mobbin.com/flows/4d8367cf-bc32-467e-8e88-360e96eabbc2) | Pairing includes verification and recovery expectations. | Useful for invalid, expired, and unreachable states. | Do not copy consumer device illustration style. |
| [Zopa Bank security setup](https://mobbin.com/screens/30de81b7-8cb4-47aa-bef7-ca29710f541c) | Security setup is framed as confidence, not punishment. | Use for biometric/notification rationale. | Do not copy banking heaviness. |
| [Gojek account protection](https://mobbin.com/screens/7cc10a1a-8641-4b89-b8fe-096aefdb51ba) | Explains protection in plain language. | Keep security copy simple. | Do not use consumer rewards/account tone. |
| [Universe first run](https://mobbin.com/screens/177cb31c-75f2-4ba2-8b5c-7be12c3d1bcf) | Product mock above setup field. | Pair code beside product preview. | Domain-signup framing. |
| [Rivian charger setup](https://mobbin.com/screens/a04cfe19-c00a-49f2-bb1a-47d202a961bf) | Device photo + time estimate. | Tie pairing to real machine object. | Consumer hardware glamour. |
| [Fitbit code entry](https://mobbin.com/screens/dd97453d-0ccf-4f87-9359-5ab12b00a479) | Minimal digits tied to physical device. | Auto-submit 6-digit code; help link. | Wearable chrome. |
| [Brave Sync QR + timer](https://mobbin.com/screens/53c3fdf5-a622-4484-aa67-8ed340ca85c0) | Temporary code expiry surfaced inline. | Show code TTL near field. | QR-first sync (V1 is code-only). |
| [Nike invalid code](https://mobbin.com/screens/5a8bda37-cd47-4c51-9363-9a79228f9b3e) | Red border + inline invalid message. | Field-adjacent pairing errors. | SMS-specific copy. |
| [Coinbase incorrect code](https://mobbin.com/screens/e76b3784-5ea8-425a-b8ca-8e268ea30a0a) | Security framing + retry. | High-trust failure copy. | Crypto branding. |
| [Meta Quest notifications flow](https://mobbin.com/flows/2de8c265-7df5-46f1-b011-5f9546f483d4) | Pre-prompt before system sheet. | Approval-alert rationale + denied path. | VR product shots. |
| [KakaoTalk expired verification](https://mobbin.com/flows/e2854335-004f-41ca-9d04-34c875b0df5b) | Expired code recovery screen. | Expired setup code recovery. | Messenger mascot tone. |

## Home / Attention Overview

| Reference | Why it matters for Lancer | Adapt | Avoid |
| --- | --- | --- | --- |
| [ClickUp task home](https://mobbin.com/screens/3e06d063-e0a2-497e-8880-167964137670) | Action items are grouped and easy to scan. | Use attention rows with task-like clarity. | Do not turn Lancer into a project-management inbox. |
| [Asana task list](https://mobbin.com/screens/76847415-87df-4ac2-aece-f0958b3f6a0d) | Clear task state, ownership, and priority cues. | Use source machine, age, and required action in rows. | Do not copy Asana's team/project labels. |
| [ClickUp list state](https://mobbin.com/screens/ddf8cb1b-0a68-4d0e-8cb4-eccab5f3969c) | Dense work list with metadata. | Useful for active runs and recent decisions. | Do not over-badge every row. |
| [Jira Cloud work list](https://mobbin.com/screens/ea9c75ca-e8fb-4f11-899d-b29c1fd55b30) | Prioritized software work is scannable on mobile. | Borrow compact severity/status treatment. | Do not copy issue-tracker ceremony. |
| [Asana work overview](https://mobbin.com/screens/7ca50f45-6c2f-467b-a4d0-1580557356ef) | Balances current work and navigation. | Keep Home focused on current attention plus active work. | Do not create a generic productivity dashboard. |
| [GitHub Inbox feed](https://mobbin.com/screens/c52d3c07-2f2f-422d-b9f1-28457b741bf5) | Repo, age, title, snippet; swipe-to-done triage. | NEEDS ATTENTION row anatomy + See all. | GitHub PR/issue types. |
| [GitHub all-done empty](https://mobbin.com/screens/67ef057b-19a1-4507-a636-6bf67241a9dd) | Calm caught-up state with return path. | All-clear Home copy + one CTA. | Illustration style. |
| [Linear Inbox](https://mobbin.com/screens/f688fc71-2060-49c2-be67-bc6ab5e53bee) | Unread dots, filter sheet, dense metadata. | Attention severity + age on rows. | Linear issue IDs. |
| [Todoist Today empty](https://mobbin.com/screens/9372f97b-a422-49e6-b9fa-4eb3d6b281fe) | Instructional empty + primary CTA. | All-clear + pair machine prompt. | Decorative illustration. |
| [Spark Mail empty folder](https://mobbin.com/screens/9742d639-4ec2-49f2-aff3-17c7a81c595b) | Thematic empty + Open/Done segments. | Pending vs recent decisions grouping. | Email IA. |
| [Brex home](https://mobbin.com/screens/b7d8dc8b-337d-4003-9f81-c52610f549c0) | Calm dashboard restraint. | Real metrics only; quiet surfaces. | Fintech chrome. |
| [monday.com My Work](https://mobbin.com/screens/2b99e73d-cd4d-4914-812b-97a10d16bd3b) | Grouped action items. | Active work module below attention. | PM taxonomy. |
| [Jira empty board](https://mobbin.com/screens/9d74be79-8a49-43c6-a6b1-26155d38ac2f) | No work + create CTA. | No machines empty state. | Jira board layout. |

## Work Thread

| Reference | Why it matters for Lancer | Adapt | Avoid |
| --- | --- | --- | --- |
| [Bolt Food delivery timeline](https://mobbin.com/screens/9509b853-f44c-425e-81c0-c6e96efffe2c) | Timestamped phase steps; current step clear. | Current state module + activity phases. | Food delivery chrome. |
| [Glovo order status](https://mobbin.com/screens/1b21deb2-e066-4ed3-a8c7-72b693406fa1) | "Now" on active step. | Running / waiting badges. | Courier copy. |
| [Shop delivery progress](https://mobbin.com/screens/54d01fb2-efe2-463b-afd4-1195ec8222de) | Summary first, detail in sheet. | Collapse raw logs. | Package tracking metaphor. |
| [Alan request timeline](https://mobbin.com/screens/751decaa-80b3-4dfd-bb78-4f39c3718578) | Events with nested supporting detail. | Approval + file events as sub-rows. | Health insurance tone. |
| [monday.com activity log](https://mobbin.com/screens/360b60f2-bc0b-48ea-9b85-202e8f3c3dcb) | Actor + field + change on one row. | Agent event row density. | Team collab labels. |
| [StubHub listing timeline](https://mobbin.com/screens/b3c71fe5-884d-4f57-85a2-8b39192d46d8) | Completed / current / future steps. | Run phase stepper. | Marketplace IA. |
| [Walmart order progress](https://mobbin.com/screens/da5c3b1c-2ff5-424f-ab22-dd8009a58e7f) | Horizontal phase strip. | Optional header phase chips. | Retail wording. |

## Work Thread

| Reference | Why it matters for Lancer | Adapt | Avoid |
| --- | --- | --- | --- |
| [GitHub PR conversation](https://mobbin.com/screens/9be4aad3-c5b8-41a3-adc5-d60a940edccb) | One durable work object with review + commits. | Link approvals, diffs, and decisions to one run. | Full PR complexity. |
| [Linear issue detail](https://mobbin.com/screens/2e52b05e-585c-42f0-bf03-5d7ae4bb4ee7) | Crisp metadata around one work item. | Machine, agent, repo, branch, state badge. | Issue-tracker fields. |

## Review / Approvals / Diff Review

| Reference | Why it matters for Lancer | Adapt | Avoid |
| --- | --- | --- | --- |
| [Airwallex approval detail](https://mobbin.com/screens/64c52224-dd85-4916-a31d-97a03c55a5c1) | Approval details put scope and consequence near the action. | Put request, scope, risk, evidence, and decision together. | Do not copy banking chrome. |
| [Remote Global HR approval](https://mobbin.com/screens/27e7a839-fea8-4c52-94a1-563816ff1bc0) | HR approvals show people, reason, and review state clearly. | Useful for actor, machine, and request reason. | Do not copy HR workflow language. |
| [Airwallex transaction approval](https://mobbin.com/screens/5678a8fc-1c54-4067-afe7-9be11682204c) | Consequence and action hierarchy are explicit. | Use persistent approve/deny actions. | Do not make Lancer feel like moving money. |
| [Revolut Business approval](https://mobbin.com/screens/9a34e3c2-65fa-49e0-9a6f-5833c749d333) | High-trust review with proportional friction. | Strong model for high/critical approvals. | Do not copy fintech styling. |
| [Airwallex approval state](https://mobbin.com/screens/94e0c040-22b2-4151-b2a9-029c5b2fcd54) | Shows a business approval state with clear metadata. | Use metadata rows for repo, command, files, machine. | Do not expose irrelevant financial fields. |

## Machines

| Reference | Why it matters for Lancer | Adapt | Avoid |
| --- | --- | --- | --- |
| [Evernote connected devices](https://mobbin.com/screens/41138583-6e7a-400f-8eba-3e2410e2bdb9) | Device list shows identity and management action. | Use machine name, device type, last seen, remove. | Do not copy note-app account framing. |
| [Chime device/session list](https://mobbin.com/screens/4cb48df6-19b1-4b19-b3d3-2e2ab311b47b) | Security-oriented device management. | Useful for trusted-device language. | Do not make Machines only an account-security page. |
| [Coupang device list](https://mobbin.com/screens/547da641-9435-4f8d-ab54-ee6c643c0b9b) | Connected devices are listed with simple state. | Use concise rows for paired machines. | Do not copy consumer streaming/account context. |
| [Coupang Play device management](https://mobbin.com/screens/2aced98c-7221-4511-853b-0d5783767940) | Device removal is accessible without being prominent. | Keep remove/revoke in detail or destructive section. | Do not put destructive actions beside daily status. |
| [Starling Bank device security](https://mobbin.com/screens/1bc58d7a-4f88-429d-932e-0cda320ab24b) | Trusted device/security state is clear. | Use for trust and revocation copy. | Do not copy banking/legal density. |

## Settings

| Reference | Why it matters for Lancer | Adapt | Avoid |
| --- | --- | --- | --- |
| [Shopee settings](https://mobbin.com/screens/9b70f0e8-058b-4952-9416-c432af6cab78) | Grouped settings keep many controls findable. | Use grouped native rows. | Do not copy marketplace clutter. |
| [MLS settings](https://mobbin.com/screens/5d8c6859-3a48-46a0-b27e-3373c9eb1b87) | Calm account/settings hierarchy. | Keep account and preferences separated. | Do not copy sports-app categories. |
| [Wise settings](https://mobbin.com/screens/d527ecba-5901-4855-b8d9-20fa2aed5702) | Professional financial app settings with clear security/account grouping. | Strong model for identity, security, notifications. | Do not copy money-transfer semantics. |
| [Revolut settings](https://mobbin.com/screens/ff9a098a-d3c2-4a8f-bd86-8714c55af083) | Dense but organized settings for a trust-heavy product. | Use clear section labels and security paths. | Do not copy upsell-heavy finance patterns. |
| [NGL settings](https://mobbin.com/screens/ddf7e4ef-a654-4f2b-82c3-7b828b34d838) | Simple grouped mobile settings. | Useful as a low-complexity baseline. | Do not copy consumer/social tone. |

## Cross-Workflow Takeaways

- Product proof beats abstract value bullets in onboarding.
- Device linking patterns should make trust boundaries and recovery obvious.
- Home should prioritize actionable attention, not generic activity.
- Mobile timelines need phase summaries and collapsed raw detail.
- Approval screens work when consequence, scope, evidence, and decision controls stay together.
- Device-management screens should show identity, last seen, trust, and revoke/remove actions.
- Settings should stay native and grouped; launch-risk billing/debug copy should not survive.
