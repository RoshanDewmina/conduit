# Attachment message design — 2026-07-14

## Objective

Render sent attachments like Claude, Gemini, and ChatGPT mobile: actual image previews above the user's text, an adaptive grid for multiple images, clean file cards for non-images, and tap-to-full-screen viewing. Internal host paths must never appear in chat bubbles, titles, accessibility labels, or user-facing errors.

This design fixes presentation and persistence. Vendor image-processing latency is a separate follow-up: the measured phone run spent about 79 seconds starting Claude Code and 63 seconds inside its JPEG `Read` tool; upload and Lancer rendering were not the bottleneck.

## Chosen approach

Use structured attachment metadata on conversation turns plus a persistent on-device preview cache.

Rejected alternatives:

- Parsing the existing `Attached files (read from disk)` prefix only is faster to build but loses reliable thumbnails after reopening and keeps transport text coupled to presentation.
- Vendor-native multimodal dispatch could reduce model latency, but combining it with the UI change expands the blast radius across every CLI adapter. It will be designed and verified separately.

## Data model and transport

Add a backward-compatible attachment reference:

```text
AttachmentRef
  id: stable UUID
  name: display filename
  mimeType: optional MIME type
  byteCount: size
  kind: image | file
  hostPath: transport-only path, never rendered
  previewCacheKey: stable phone cache key
```

Conversation append requests carry:

- `prompt`: the clean user-authored text used for storage, titles, and rendering.
- `attachments`: optional structured references.

The daemon constructs the effective vendor prompt from the clean prompt plus attachment host paths. It persists the clean prompt and attachment metadata in the conversation turn. Existing requests without attachments remain unchanged.

The wire envelope adds optional attachment metadata. Older daemon/app combinations decode it as absent. Historical turns that contain the legacy path prefix are displayed with the prefix removed; recognized filenames become clean file cards, but no image is fabricated when bytes are unavailable.

## Phone-side preview cache

When the user selects an image:

1. Keep the existing upload state machine.
2. Generate a bounded preview off the main actor while the original bytes are available.
3. Store the preview under the attachment's stable cache key in Application Support.
4. Persist only metadata and the cache key in the turn.

The cache survives app relaunches. Missing or evicted previews degrade to a clean image/file card with filename and size—never to an absolute path. Cross-device thumbnail retrieval is outside this beta fix; it can later use a governed `attachment.get` RPC.

## Rendering

Introduce one reusable user-message view used by live and historical transcripts:

- One image: prominent rounded preview above the prompt, preserving aspect ratio.
- Two or more images: compact two-column adaptive grid.
- Non-image files: icon, filename, type, and size card.
- Mixed attachments: image grid followed by file cards.
- Tap an image: system-style full-screen preview with aspect-fit content and a Close action.
- Uploading/error states remain in the composer chips; sent-message cards represent only successfully uploaded attachments.

The clean prompt remains selectable and accessible below the attachment strip. Accessibility labels use attachment type, filename, and size. Dynamic Type changes labels without shrinking the preview into a narrow column.

## Error handling and safety

- Failed uploads do not dispatch and do not produce sent attachment metadata.
- Missing previews show a neutral placeholder/file card.
- Unsupported MIME types render as files.
- Preview decoding/downscaling failures do not block dispatch.
- Absolute paths are transport-only and excluded from UI, titles, accessibility, and analytics.
- Preview generation is bounded by pixel dimensions and runs off the main actor.
- No change is made to approval policy, relay pairing, or file access outside already uploaded attachment paths.

## Likely write set

- iOS attachment models/upload result and preview-cache support.
- Composer and follow-up send paths.
- Shared user-message bubble used by `LiveThreadView` and `ThreadDetailView`.
- Conversation turn persistence/wire models.
- Daemon conversation append/store/fetch path that separates clean and effective prompts.
- Focused attachment model, persistence, compatibility, and rendering-policy tests.

The work must not overlap the active transcript-hydration or Review file-viewer fixes. Integration happens only after those branches land or after a conflict-aware rebase.

## Verification

Test-first requirements:

- Clean prompt is stored/rendered while vendor dispatch receives attachment paths.
- Attachment metadata round-trips through daemon fetch and iOS persistence.
- Legacy prefixed turns hide absolute paths.
- One/multiple/mixed layout policy is deterministic.
- Missing cache entries fall back to clean cards.
- Preview cache survives recreation and bounds image dimensions.
- No user-facing string contains `.lancer/attachments/` or an absolute host path.

Release gates:

- Focused RED/GREEN tests on iOS and daemon.
- Full affected Swift and Go suites.
- LancerKit build and iOS app-target build.
- Simulator screenshots for one image, multiple images, file-only, missing preview, and Dynamic Type.
- Physical-phone round-trip, relaunch persistence, full-screen preview, and accessibility spot check.
- `git diff --check`; no generated `Package.resolved` drift.

## Done when

A user can attach an image, send it, see the real preview above clean prompt text, reopen the conversation and still see the preview, tap it full-screen, and never see the host attachment path. Non-image files remain understandable and actionable without pretending to be image previews.
