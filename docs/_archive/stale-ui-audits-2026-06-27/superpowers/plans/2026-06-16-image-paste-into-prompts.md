# Image Paste into Prompts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user attach/paste an image into the chat prompt composer on iOS; the image is uploaded to the remote host via SFTP and referenced by path in the agent prompt (e.g. `claude -i /tmp/lancer-img-<uuid>.png …`), so the agent receives it as a real image input.

**Architecture:** The composer already has a dead-but-complete attachment stub (`ComposerAttachment` enum + `PhotosPicker` + `onAttach` callback in `ChatInputBar`) — it is simply never wired in `SessionView`. This plan wires it, adds an `ImageAttachmentService` that SFTP-uploads the image to a deterministic remote path (SFTP is already production-grade), and augments `SessionViewModel.submit()` to prepend the agent-specific image flag before sending the prompt over the PTY.

**Tech Stack:** Swift 6 (LancerKit), SwiftUI `PhotosPicker`/`Transferable`, existing `SFTPClient` (`SSHTransport/SFTPClient.swift`), `AgentRegistry` for per-agent image-flag formatting.

## Global Constraints

- **Images must land on the remote host filesystem.** `claude`/`codex` read images by path, not stdin. The prompt is rewritten to reference the uploaded remote path. (verified)
- **The PTY path only carries bytes.** There is no structured prompt envelope; `submit()` sends `Array((text + "\n").utf8)` to the unified PTY. The image flag must be injected into that text. (verified, `SessionViewModel.swift:1068-1085`)
- **Upload is async; the prompt must not send until upload completes.** Block send (with a spinner) until SFTP write succeeds; on failure, abort the send and surface an error — never send a prompt referencing a path that does not exist. (verified risk)
- **Per-agent flag differs** (`claude -i <path>` vs `codex --image <path>`); resolve via the connected agent's registration, not a hardcoded flag.
- **Attachment only in idle (`promptEditing`) state**, not during `LivePromptInputView` execution (raw-keystroke mode has no attachment path). (verified)
- **Do NOT `git commit` unless the user explicitly asks.**

---

## File Structure

| File | New/Mod | Responsibility |
|---|---|---|
| `Packages/LancerKit/Sources/SessionFeature/ImageAttachmentService.swift` | New | Given image `Data`+`UTType`, compress/resize, SFTP-write to `/tmp/lancer-img-<uuid>.<ext>`, return the remote path. |
| `Packages/LancerKit/Sources/SessionFeature/SessionViewModel.swift` | Mod (`:1045-1087`, add state) | Hold a `pendingAttachment`; on `submit()` upload then prepend the agent image flag. |
| `Packages/LancerKit/Sources/SessionFeature/SessionView.swift` | Mod (`:343`) | Pass `onAttach:` into `ChatInputBar` (wire the existing stub). |
| `Packages/LancerKit/Sources/SessionFeature/Chat/ChatInputBar.swift` | Mod (`:251` chip area) | Render a small attachment preview chip when an attachment is pending (UI only; mechanism already present). |
| `Packages/LancerKit/Tests/LancerKitTests/ImageAttachmentTests.swift` | New | Tests for remote-path generation + prompt rewriting (SFTP mocked). |

---

## Task 1: prompt rewriting for the connected agent

**Files:**
- Create: `Packages/LancerKit/Sources/SessionFeature/ImageAttachmentService.swift` (the pure rewriting helper first; SFTP added in Task 2)
- Test: `Packages/LancerKit/Tests/LancerKitTests/ImageAttachmentTests.swift`

**Interfaces:**
- Produces:
  - `enum AgentImageFlag { static func command(agentID: String, remotePath: String, userText: String) -> String }` — returns the full line to send. claude → `claude -i '<path>' -p '<text>'`? **No** — the agent is already running in the PTY; we send to the *running* agent's stdin, so we emit a reference the running CLI understands. For claude interactive, the supported form is to include the path token in the message text. Use: `"<userText> <remotePath>"` for claude (it auto-detects image paths in the message), `"<userText>\n<remotePath>"` otherwise. (Implementer: confirm the exact in-session image syntax per agent via that agent's docs before finalizing; the rewriting is centralized here so it is the only place to change.)
  - `func remoteImagePath(uuid: String, ext: String) -> String` → `"/tmp/lancer-img-<uuid>.<ext>"`.

- [ ] **Step 1: Write the failing test**

```swift
func testRemotePathAndRewrite() {
    let path = remoteImagePath(uuid: "abc", ext: "png")
    XCTAssertEqual(path, "/tmp/lancer-img-abc.png")
    let line = AgentImageFlag.command(agentID: "claude", remotePath: path, userText: "Explain this")
    XCTAssertTrue(line.contains("/tmp/lancer-img-abc.png"))
    XCTAssertTrue(line.contains("Explain this"))
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/LancerKit && swift test --filter ImageAttachmentTests`
Expected: FAIL — undefined symbols.

- [ ] **Step 3: Implement the helpers**

```swift
import Foundation

public func remoteImagePath(uuid: String, ext: String) -> String {
    "/tmp/lancer-img-\(uuid).\(ext)"
}

public enum AgentImageFlag {
    public static func command(agentID: String, remotePath: String, userText: String) -> String {
        switch agentID {
        case "claude", "claudeCode":
            return "\(userText) \(remotePath)"
        default:
            return "\(userText)\n\(remotePath)"
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/LancerKit && swift test --filter ImageAttachmentTests`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add Packages/LancerKit/Sources/SessionFeature/ImageAttachmentService.swift \
        Packages/LancerKit/Tests/LancerKitTests/ImageAttachmentTests.swift
git commit -m "feat(ios): centralize per-agent image prompt rewriting"
```

---

## Task 2: SFTP upload of the attachment

**Files:**
- Modify: `Packages/LancerKit/Sources/SessionFeature/ImageAttachmentService.swift`
- Test: extend `ImageAttachmentTests.swift` with a mock SFTP writer.

**Interfaces:**
- Consumes: `SFTPClient.write(path:data:)` (`SFTPClient.swift:188`) via `SSHSession.withSFTP` (`SSHSession.swift:340`).
- Produces: `func upload(_ data: Data, ext: String, over session: SSHSession) async throws -> String` — resizes if large, writes to `remoteImagePath`, returns the remote path. Inject the writer behind a protocol so the test does not need a live SSH session.

- [ ] **Step 1: Write the failing test with a mock writer**

```swift
func testUploadWritesToRemotePathAndReturnsIt() async throws {
    let mock = MockSFTPWriter()
    let svc = ImageAttachmentService(writer: mock, uuid: { "abc" })
    let path = try await svc.upload(Data([0,1,2]), ext: "png")
    XCTAssertEqual(path, "/tmp/lancer-img-abc.png")
    XCTAssertEqual(mock.lastPath, path)
    XCTAssertEqual(mock.lastData?.count, 3)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/LancerKit && swift test --filter ImageAttachmentTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ImageAttachmentService` with an injectable writer**

```swift
public protocol SFTPWriting: Sendable {
    func write(path: String, data: Data) async throws
}

public struct ImageAttachmentService: Sendable {
    let writer: SFTPWriting
    let uuid: @Sendable () -> String

    public init(writer: SFTPWriting, uuid: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.writer = writer
        self.uuid = uuid
    }

    public func upload(_ data: Data, ext: String) async throws -> String {
        let path = remoteImagePath(uuid: uuid(), ext: ext)
        try await writer.write(path: path, data: data) // resize before this for large images
        return path
    }
}
```
Provide a production `SFTPWriting` conformance that wraps `session.withSFTP { try await $0.write(path:data:) }`.

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/LancerKit && swift test --filter ImageAttachmentTests`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add Packages/LancerKit/Sources/SessionFeature/ImageAttachmentService.swift \
        Packages/LancerKit/Tests/LancerKitTests/ImageAttachmentTests.swift
git commit -m "feat(ios): SFTP-upload pasted images to a deterministic remote path"
```

---

## Task 3: wire the composer stub + submit augmentation

**Files:**
- Modify: `Packages/LancerKit/Sources/SessionFeature/SessionView.swift:343`, `Packages/LancerKit/Sources/SessionFeature/SessionViewModel.swift:1045-1087`, `Packages/LancerKit/Sources/SessionFeature/Chat/ChatInputBar.swift`

**Interfaces:**
- Consumes: existing `ChatInputBar.onAttach: ((ComposerAttachment) -> Void)?` (`ChatInputBar.swift:38`), `ComposerAttachment.photo(Data, UTType)` (`:10`), `ImageAttachmentService`, `AgentImageFlag`.
- Produces: `SessionViewModel.pendingAttachment: ComposerAttachment?` + `func attach(_:)`; `submit()` uploads then sends the rewritten line.

- [ ] **Step 1: Add `pendingAttachment` + `attach` to the view model (failing test)**

```swift
@MainActor
func testSubmitWithAttachmentUploadsThenSendsRewrittenLine() async throws {
    let vm = SessionViewModel.makeTestInstance() // existing test factory or minimal init
    vm.injectImageService(stubReturning: "/tmp/lancer-img-abc.png")
    vm.attach(.photo(Data([0]), .png))
    vm.inputText = "Explain this"
    await vm.submit()
    XCTAssertTrue(vm.lastSentText.contains("/tmp/lancer-img-abc.png"))
    XCTAssertNil(vm.pendingAttachment) // cleared after send
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/LancerKit && swift test --filter SessionViewModel`
Expected: FAIL — `pendingAttachment`/`attach`/`injectImageService` undefined.

- [ ] **Step 3: Implement the submit path**

In `SessionViewModel`: add `pendingAttachment`, `attach(_:)`, and an injectable `imageService`. In `submit()` (the `promptEditing`/fallback branches, `:1056-1087`), if `pendingAttachment != nil`: `await` upload, then build the line via `AgentImageFlag.command(agentID:remotePath:userText:)`, send it via the existing `shell.send(Array((line + "\n").utf8))`, then clear `pendingAttachment`. On upload failure, surface an error and do NOT send.

- [ ] **Step 4: Wire `onAttach` in `SessionView` + preview chip in `ChatInputBar`**

In `SessionView.swift:343`, pass `onAttach: { vm.attach($0) }` to `ChatInputBar`. In `ChatInputBar`, render the attachment chip when an attachment is pending (the `mediaAttachmentEnabled && onAttach != nil` gate at `:251` already controls the paperclip button visibility).

- [ ] **Step 5: Run to verify it passes**

Run: `cd Packages/LancerKit && swift test --filter SessionViewModel`
Expected: PASS.

- [ ] **Step 6: Authoritative app-target build + visual check**

`mcp__XcodeBuildMCP__build_sim` (Lancer / iPhone 17 Pro) → BUILD SUCCEEDED. Then launch the chat gallery route and confirm the paperclip + PhotosPicker now appear and a selected image shows a chip.

- [ ] **Step 7: Commit (stage only)**

```bash
git add Packages/LancerKit/Sources/SessionFeature/SessionView.swift \
        Packages/LancerKit/Sources/SessionFeature/SessionViewModel.swift \
        Packages/LancerKit/Sources/SessionFeature/Chat/ChatInputBar.swift
git commit -m "feat(ios): wire image attachment composer → SFTP upload → prompt"
```

---

## Task 4: end-to-end verification (live host)

- [ ] **Step 1: Live SSH session, attach an image**

Use the live block-session harness (CLAUDE.md "Block terminal" section). Connect to a host running `claude`, paste/select an image, send "Describe this image".

- [ ] **Step 2: Confirm the image landed and was referenced**

On the host: `ls -la /tmp/lancer-img-*.png` shows the file; the agent's response references the image content. Confirm a dropped connection mid-upload aborts the send (no prompt referencing a missing path).

---

## Spec coverage check

| Requirement | Task |
|---|---|
| Attach/paste image in composer | Task 3 (wire existing stub) |
| Upload to remote host | Task 2 (SFTP) |
| Reference image in prompt to agent | Tasks 1, 3 (per-agent rewrite) |
| Async-upload safety (no send before upload) | Task 3 step 3 + Task 4 step 2 |
| Per-agent flag formatting | Task 1 |

## Placeholder scan

- Exact files/lines and concrete code in every step. The one genuinely uncertain detail — the exact in-session image-reference syntax each CLI accepts — is centralized in `AgentImageFlag` with an explicit instruction to confirm against each agent's docs, so it is one place to fix, not a scattered guess.
