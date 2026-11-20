# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.9] - 2026-11-20

### Fixed
- **Thought Duration Accuracy**: Avoided recording fake `0.1s` durations during historical `session/load` replay or sub-200ms single-chunk emissions; historical thoughts now cleanly show `Thought` while live thinking shows actual elapsed duration.
- **Session History Reliability**:
  - Added `_ensureEventSubscription` so `openSession` reuses an active event stream instead of canceling and recreating it right before `session/load` (which previously dropped replayed history events during stream re-registration).
  - Marked newly created sessions as loaded in `loadedRealSessions` so navigating back and reopening them preserves in-memory history.
  - Restored previous messages if `session/load` fails instead of wiping history on transient errors.

## [1.0.8] - 2026-11-20

### Fixed
- **Thought Card Duration & Trailing Whitespace**:
  - Tracked actual elapsed thinking time so the header displays `Thought for Xs` (or `Thought` when duration isn't available) instead of `Thought for Reasoning`.
  - Trimmed trailing newlines from thought text and removed extra bottom padding inside expanded reasoning cards.
- **Hide Output on All Tool Calls by Default**:
  - Converted edit diff cards (`_EditToolCard`) to collapsible cards with diff output hidden by default, matching shell tool cards (`_TerminalToolCard`).
- **Workspace Folder & File Browsing**:
  - Updated the Workspace Files tab to distinguish folders (`isDir`) from files: tapping a folder navigates into it via `workspace/tree` with a parent (`..`) navigation bar, while tapping a file opens a preview sheet via `workspace/read_file` and `@ Attach` attaches it to chat.

## [1.0.7] - 2026-11-20

### Changed
- **Chat Screen & Tool Call Polish**:
  - Made shell tool call cards (`_TerminalToolCard`) collapsible with output hidden by default, clean status indicators, and expandable scrollable monospace output.
  - Polished edit diff cards (`View full diff →` footer bar) and cleaned permission cards (`Permission Required`, removed `Approval Required · Tool Permission` and `cwd:` slop).
  - Removed `/tmp` slop from chat empty state, composer toolbar (`Upload /tmp` → `Attach`), and attached upload chips (removed `(/tmp)` suffix).
  - Redesigned composer toolbar (`_MiniToolChip`, `_AttachedChip`, gradient send button, clean input wrap) and `Mode & Model` bottom sheet (custom selectable mode pills and model list cards) to match the approved `Orbital Carbon` / `Studio Daylight` design.
  - Replaced remaining `ActionChip` diff badge, `Latest` button, and `NewSessionSheet` workspace root `ChoiceChip`s with design-system components.

## [1.0.6] - 2026-11-20

### Fixed
- **Compact `agyd pair` Terminal QR Code**:
  - Filtered out loopback (`127.0.0.1`, `::1`), unspecified (`0.0.0.0`, `::`), and link-local IPv6 (`fe80:`) addresses from `DirectAddrs()`.
  - Added `CompactPairURI` (capped to 2 IPv4-preferred direct addresses + 1 relay address) and switched `RenderTerminalQR` to `qrcode.Low` with `DisableBorder = true` so the QR code fits comfortably inside standard `80x24` terminals.

### Changed
- **Aligned Mobile UI with Approved Design (`Orbital Carbon` / `Studio Daylight`)**:
  - Replaced Material 3 default `FilledButton` / `FloatingActionButton.extended` with `GradientPillButton` (`999px` pill, `#38BDF8` → `#6366F1` gradient, cyan glow shadow) and `GradientBlockButton` (`12px` radius gradient buttons).
  - Replaced Material 3 `ChoiceChip` filters (`All`, `Active`, `Needs Approval`) with compact `AgyFilterChip` pills (`11.5px`, no checkmarks, accent-soft active state).
  - Replaced Material 3 `SegmentedButton` with `AgySegmentedControl` (`surfaceRaised` track, `surface` active tab, no checkmarks).
  - Replaced `ActionChip` host switcher with a compact pill switcher matching `.host-switcher-pill`.
  - Replaced Material 3 `NavigationBar` with a `58px` bottom navigation bar (`navBg` + top border, no indicator pill blob, amber pending-approval badge).

## [1.0.5] - 2026-11-20

### Removed
- **Removed Send Test Alert Button**: Removed the `"Send Test Alert"` tile and test button from the Settings screen.

## [1.0.4] - 2026-11-20

### Fixed
- **QR Scanner in Release APK (`Camera unavailable`)**: Disabled R8 code/resource shrinking (`isMinifyEnabled = false`, `isShrinkResources = false`) in Android release builds so CameraX and Google ML Kit barcode classes/providers are never stripped or obfuscated into `NullPointerException`. Managed explicit `MobileScannerController` lifecycle and added retry support + diagnostic error details.
- **Prevent Creating Sessions Without Paired Host**:
  - Hidden the "New Session" FAB and displayed a "No Paired Host" onboarding prompt with a "Pair Machine" button on the Sessions tab when no host is paired.
  - Guarded `AppController.createNewSession` with `StateError` when `activeHost == null` and disabled session creation in `NewSessionSheet` when no host is available.

## [1.0.3] - 2026-11-20

### Removed
- **Removed Demo Setting in Production**: Completely hid and disabled the "Show Preview Demo Host" setting toggle in production release builds (`kReleaseMode`), and guaranteed clean initial state without mock hosts or sessions.
- **Removed UI Subtitle Slop**:
  - Removed `Zero-trust Ed25519 + SAS verification` under "Pair Remote Machine" in pair sheet.
  - Removed `${state.hosts.length} Host(s)` under "Paired Machines" in hosts screen.
  - Removed hardcoded mock repository path fallback (`~/dev/antigravity-mobile · main`) in workspace screen.

### Changed
- **De-Jargonized UI Titles & Subtitles**:
  - Renamed `MOBILE NODE IDENTITY (go-libp2p)` to `DEVICE IDENTITY` and status badge to `Online`.
  - Renamed `DCUtR Hole Punching` to `Direct P2P Hole Punching` and cleaned up NAT/relay explanation subtitles.
  - Renamed `SHORT AUTHENTICATION STRING (SAS)` to `SECURITY VERIFICATION CODE`.
  - Removed CLI argument flags `(--sandbox)` and daemon binary tags `(agy-relay)` from UI titles.
  - Cleaned up file upload modal to user-facing copy without internal protocol multiaddrs (`/agy/blob/1.0.0`) or staging paths.

## [1.0.2] - 2026-11-20

### Fixed
- **Camera Permission for QR Scanner**: Implemented native Android runtime camera permission requests via `AndroidRuntime` method channel on `MainActivity`. `MobileScanner` is now safely gated until permission is granted, preventing CameraX `NullPointerException` crashes and "Camera unavailable" errors on physical Android devices.
- **Hide Demo Machines in Production**: Set default `showDemoHost` to `kDebugMode`. Release builds on real devices now start with a clean onboarding screen without mock hosts or fake sessions. Persisted user preference in `SharedPreferences`.

### Changed
- **Removed UI Subtitle Clutter**: Cleaned up header text by removing `Noise XX End to End Encrypted` under Paired Machines on the Hosts screen and `Identity, Relays & NAT Policies` under Settings.
- **Enhanced Camera Manifest Compatibility**: Declared `android.hardware.camera.autofocus` and `android.hardware.camera.front` as non-required features in `AndroidManifest.xml` for wider device compatibility.

## [1.0.1] - 2026-11-20

### Changed
- **Optimized APK Size**: Removed unstripped native debug symbols and excluded unneeded ABIs, reducing APK size from ~206MB down to ~50MB.
- **Split ABI Releases**: Added `--split-per-abi` release targeting to produce lean per-architecture APKs.
- **Platform-Tagged Go Binaries**: `agyd` and `agy-relay` binaries are now named and built with target OS and architecture (`linux-amd64`, `linux-arm64`, `darwin-amd64`, `darwin-arm64`, `windows-amd64`, `windows-arm64`).
- **Release Checksums**: Automatic generation of `release-checksums.txt` with SHA-256 digests.

## [1.0.0] - 2026-11-20

### Added
- **Flutter Android Client (`xyz.luaan.antigravitymobile`)**:
  - Full mobile UI supporting multiple workspaces, sessions, streaming chat, and tool permission approvals.
  - P2P communication via C-shared `libagyp2p.so` over `go-libp2p` Dart FFI bindings.
  - Android Foreground Service (`AgyForegroundService`) with Partial WakeLock during active ACP streaming.
  - Native alerts and lifecycle reconnection management.
  - Zero-G Delta "A" launcher icon and Android adaptive icon resources.
- **Go Host Daemon (`agyd`)**:
  - Host process orchestrating local `agy acp --stdio` instances per session.
  - Pairing protocol with terminal QR code generation, URI links, and SAS verification.
  - Multi-workspace and git status/diff RPC handlers.
  - Isolated `/tmp/agyd-uploads/<session-id>/` staging for mobile file and photo uploads.
  - Persistent `systemd --user` service installer (`agyd install-service`).
- **Self-Hosted Circuit Relay v2 (`agy-relay`)**:
  - Lightweight relay daemon with AutoNAT and Circuit Relay v2 over QUIC v1 and TCP.
  - Optional hot-reloadable PeerID allowlist (`--allow-file`) responding to `SIGHUP`.
  - Docker Compose deployment bundle under `deploy/relay/`.
- **CI / CD**:
  - Automated GitHub Actions workflow (`.github/workflows/release-apk.yml`) building signed Android `arm64-v8a` APK, `agyd`, and `agy-relay` binaries with release verification.
