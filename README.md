# Antigravity Mobile (`xyz.luaan.antigravitymobile`)

[![Release Android APK & Go Binaries](https://github.com/luank3/antigravity-mobile/actions/workflows/release-apk.yml/badge.svg)](https://github.com/luank3/antigravity-mobile/actions/workflows/release-apk.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Mobile client for **Antigravity CLI (`agy`)** built with **Flutter (Android `arm64-v8a`)** and **Go (`agyd` + `agy-relay`)**, connected end-to-end over **libp2p** (Noise `XX`, Yamux, QUIC v1 / TCP, mDNS LAN discovery, DCUtR hole punching, and Circuit Relay v2 for symmetric NATs).

---

## Architecture & Components

```
┌─────────────────────────────────┐                 ┌─────────────────────────────────┐
│     Antigravity Mobile App      │                 │      Host Daemon (`agyd`)       │
│  (Flutter / Dart / Material 3)  │                 │    (Go / Systemd Background)    │
│  Package:                       │                 │                                 │
│  xyz.luaan.antigravitymobile    │                 │  Manages workspaces, ACP        │
│                                 │                 │  sessions & permission prompts  │
└────────────────┬────────────────┘                 └────────────────┬────────────────┘
                 │                                                   │
                 │ Dart FFI                                          │ Local Pipe
                 ▼                                                   ▼
┌─────────────────────────────────┐      libp2p     ┌─────────────────────────────────┐
│   Go Bridge (`libagyp2p.so`)    │◄───────────────►│  `agy acp --stdio --process...` │
│    C-shared libp2p transport    │   Direct LAN    └─────────────────────────────────┘
└────────────────┬────────────────┘   or Relay v2                    ▲
                 │                         ▲                         │
                 │                         │                         │
                 └─────────────────────────┼─────────────────────────┘
                                           │
                         ┌─────────────────┴─────────────────┐
                         │   Circuit Relay v2 (`agy-relay`)  │
                         │    Self-Hosted (Docker / VPS)     │
                         │      AutoNAT & PeerID ACL         │
                         └───────────────────────────────────┘
```

- **`mobile/`**: Flutter Android client (`xyz.luaan.antigravitymobile`) featuring:
  - Material 3 dark-mode UI with streaming markdown and code syntax highlighting.
  - Interactive tool permission cards (`Allow Once`, `Allow for Session`, `Deny`).
  - Native foreground service (`AgyForegroundService`) with partial WakeLock during ACP turns.
  - Multi-workspace and session switcher with photo/log file attachment staging.
  - Zero-G Delta "A" adaptive icons.
- **`server/cmd/agyd/`**: Host daemon running alongside `agy acp --stdio`, managing pairing allowlists, ACP streaming/permissions, workspace/git RPCs, `systemd --user` service installation, and staging mobile uploads in `/tmp/agyd-uploads/<session-id>/`.
- **`server/cmd/agy-relay/`**: Lightweight self-hosted Circuit Relay v2 and AutoNAT server (unlimited ACL-gated relay bandwidth for mobile 5G CGNAT and symmetric NAT traversals).
- **`server/pkg/mobilebridge/`**: C-shared `go-libp2p` core (`libagyp2p.so`) consumed by Flutter via Dart FFI.
- **`deploy/relay/`**: Production Docker + Docker Compose bundle for `agy-relay`.
- **`docs/`**: Architecture design plans ([`docs/DESIGN_PLAN.md`](docs/DESIGN_PLAN.md)).

---

## Quick Start

### 1. Deploy Self-Hosted Relay (`agy-relay`) on a VPS (Optional for LAN)

Using Docker Compose with hot-reloadable PeerID allowlist (`--allow-file /data/allowed_peers.txt`):

```bash
cd deploy/relay
AGY_RELAY_HOST=relay.example.com docker compose up -d --build
docker compose logs -f agy-relay
```

Or deploy remotely over SSH in one command:

```bash
ALLOW_PEERS="<HostPeerID>,<MobilePeerID>" ./scripts/deploy_vps_relay.sh relay.example.com
```

Firewall requirements: Open **4001/tcp** and **4001/udp** on your VPS.

### 2. Run or Install Host Daemon (`agyd`) on Your PC / Workstation

Foreground execution:

```bash
cd server
go run ./cmd/agyd run \
  --workspace ~/dev/your-project \
  --relay /dns4/relay.example.com/udp/4001/quic-v1/p2p/<RelayPeerID>
```

Install as a persistent background `systemd --user` service:

```bash
cd server
go build -o ~/.local/bin/agyd ./cmd/agyd
~/.local/bin/agyd install-service \
  --workspace ~/dev/your-project \
  --relay /dns4/relay.example.com/udp/4001/quic-v1/p2p/<RelayPeerID>
sudo loginctl enable-linger $USER
```

Check status anytime: `agyd status` or `systemctl --user status agyd.service`.

### 3. Pair Your Android Device

Generate a pairing invitation on your workstation:

```bash
agyd pair
```

Open **Antigravity** on Android → **Hosts** → **+ Pair** → scan the terminal QR code (or paste the `agy://pair?...` URI / use Nearby LAN mDNS + PIN) → verify the 6-digit + emoji SAS code matches.

---

## Building from Source

### Native Mobile Bridge (`libagyp2p.so`)

Building the C-shared native library requires Go (with CGO) and the Android NDK:

```bash
export ANDROID_NDK_ROOT="/path/to/android-sdk/ndk/28.2.13676358"
./scripts/build_mobilebridge.sh
```

### Android APK (`arm64-v8a`)

```bash
cd mobile
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Output: `mobile/build/app/outputs/flutter-apk/app-release.apk`.

> **Note on Local vs CI Builds**: Upstream Flutter does not ship a `linux-arm64/gen_snapshot` binary for building `--release` AOT APKs directly on `linux/aarch64` hosts. On `linux/aarch64` machines, use `--debug` for testing. Signed production `--release` APKs are built automatically via the [GitHub Actions Release Pipeline](.github/workflows/release-apk.yml) on `ubuntu-latest`.

---

## Release Signing

For local release signing, configure `mobile/android/key.properties`:

```properties
storeFile=release.jks
storePassword=<store-password>
keyAlias=<key-alias>
keyPassword=<key-password>
```

In GitHub Actions, the pipeline decodes `ANDROID_KEYSTORE_BASE64` and signs the release APK automatically.

---

## Community & Contributing

- Check out our [Contributing Guidelines](CONTRIBUTING.md).
- See the [Changelog](CHANGELOG.md) for version history.
- Read our [Security Policy](SECURITY.md) to report vulnerabilities.

---

## License

Antigravity Mobile is open-source software licensed under the [Apache License, Version 2.0](LICENSE).
