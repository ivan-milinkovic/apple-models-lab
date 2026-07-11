# ModelLab — Agent Instructions

SwiftUI sandbox app for trying out Apple's on-device ML frameworks: **FoundationModels** (on-device LLM) for chat/suggestions/tagging, and **Vision + AVFoundation** for live camera face/pose detection. Plain Xcode project (no SPM package), targets iOS, macOS, and visionOS.

## Build & run

```bash
xcodebuild -project ModelLab.xcodeproj -scheme ModelLab -destination 'platform=macOS' build
```

Use `-destination 'platform=iOS Simulator,name=...'` for iOS. There are two schemes: `ModelLab` (Debug) and `ModelLab Release Run`. FoundationModels APIs require a real Apple Intelligence-capable device/OS; behavior may differ or be unavailable in the simulator.

Deployment target is iOS/macOS **26.5 (beta)** — this project relies on very recent/beta APIs (`FoundationModels`, `@Generable`, `AVCaptureDevice.RotationCoordinator`). Don't "fix" beta API usage by downgrading to older equivalents without asking.

## Architecture

Each feature is a self-contained folder: `Feature/FeatureModel.swift` + `Feature/FeatureView.swift` (e.g. [Chat/ChatModel.swift](ModelLab/Chat/ChatModel.swift) + [Chat/ChatView.swift](ModelLab/Chat/ChatView.swift)). Follow this pairing for new features.

- Models are `@Observable @MainActor final class`, typically exposed as `static let shared`.
- Long-lived non-trivial resources (LLM sessions, camera objects) are marked `@ObservationIgnored` so they don't trigger spurious view redraws.
- Background/hardware-facing services are Swift `actor`s, not classes with locks — see [Vision/CameraService.swift](ModelLab/Vision/CameraService.swift).
- Navigation is a single enum-based router in [ContentView.swift](ModelLab/ContentView.swift) using `NavigationSplitView`.

### FoundationModels usage (Chat/Suggestions/Tagging)

- Call `session.prewarm()` right after creating a `LanguageModelSession` to cut first-prompt latency.
- Use `session.streamResponse()` for interactive/streaming UIs (Chat), `session.respond()` for one-shot results (Suggestions, Tagging).
- For structured output, define a `@Generable` struct with `@Guide` annotations and call `session.respond(..., generating: MyType.self)` — see [Tagging/TaggingModel.swift](ModelLab/Tagging/TaggingModel.swift).

### Vision + camera pipeline (see [Vision/](ModelLab/Vision))

Non-obvious, hard-won architecture — read before touching camera/rotation code (full history in repo memory, ask to consult `/memories/repo/vision-overlay-notes.md` if available):

- `VisionViewModel` instantiates the `AVCaptureVideoPreviewLayer` (it's UI-affined and must not be owned by an actor) and hands it to `CameraService.setup(previewLayer:)`.
- `CameraService` (an `actor`) owns and configures **everything else**: session, device, `AVCaptureVideoDataOutput`, and a single `AVCaptureDevice.RotationCoordinator`. It applies `videoRotationAngleForHorizonLevelPreview` (not the `...Capture` variant) to **both** the preview connection and the output connection together, keeping them in sync via KVO. Keep all connection/rotation logic centralized here — splitting it back out previously caused race conditions (a rotation observer locking onto a stale/nil connection).
- Non-`Sendable` AVFoundation types (`CMSampleBuffer`, `AVCaptureVideoPreviewLayer`) cross the actor boundary wrapped in `SendableWrapper<T>: @unchecked Sendable`; `@preconcurrency import AVFoundation` suppresses noise from the framework's own incomplete sendability annotations. Follow this pattern for any new actor-crossing AVFoundation calls.
- Since the output connection now delivers an already-rotated/upright pixel buffer, `VNImageRequestHandler` orientation is fixed at `.up`, and Vision point mapping in [Vision/VisionView.swift](ModelLab/Vision/VisionView.swift) uses manual aspect-fill math (`mapPoint`/`aspectFillTransform`) against real per-frame `CVPixelBuffer` dimensions — **do not** replace this with `AVCaptureVideoPreviewLayer` conversion methods (`layerRectConverted(fromMetadataOutputRect:)` etc.); that reintroduces dependence on live connection state, which is exactly what previously caused hard-to-debug rotation/mirroring bugs.
- `CameraPreview.swift` is intentionally a "dumb" view — it only hosts the already-configured preview layer as a sublayer. Don't add rotation/session logic back into it.
