# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
