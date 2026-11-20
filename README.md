# Antigravity Mobile (`agy-mobile`)

Mobile client for **Antigravity CLI (`agy`)** built with **Flutter (Android `arm64-v8a`)** and **Go (`agyd` + `agy-relay`)**, connected end-to-end over **libp2p** (Noise `XX`, Yamux, QUIC v1 / TCP, mDNS LAN discovery, DCUtR hole punching, and Circuit Relay v2 for symmetric NATs).

## Components

- `server/cmd/agyd/` — Host daemon running alongside `agy acp --stdio --process-per-session`, managing pairing allowlists, ACP streaming/permissions, workspace/git RPCs, systemd user service install, and isolated `/tmp/agyd-uploads/<session-id>/` staging for mobile file uploads.
- `server/cmd/agy-relay/` — Lightweight self-hosted Circuit Relay v2 + AutoNAT server (unlimited ACL-gated relay bandwidth for dual symmetric NAT / mobile 5G CGNAT).
- `deploy/relay/` — Production Docker + Docker Compose bundle for `agy-relay`.
- `server/pkg/mobilebridge/` — C-shared `go-libp2p` core (`libagyp2p.so`) consumed by Flutter via Dart FFI.
- `mobile/` — Flutter Android client (`xyz.luaan.antigravitymobile`) with foreground keepalive service, partial WakeLock while streaming, background approval/completion alerts, and lifecycle reconnect.
- `docs/DESIGN_PLAN.md` — Architecture and UX design plan.

## Quick Start

### 1. Deploy Self-Hosted Relay (`agy-relay`) on a VPS (Optional for LAN)

Using Docker Compose (with optional hot-reloadable PeerID ACL via `--allow-file /data/allowed_peers.txt` and `docker kill -s HUP agy-relay`):

```bash
cd deploy/relay
AGY_RELAY_HOST=relay.example.com docker compose up -d --build
docker compose logs -f agy-relay
```

Or deploy remotely over SSH in one command:

```bash
ALLOW_PEERS="<HostPeerID>,<MobilePeerID>" ./scripts/deploy_vps_relay.sh relay.example.com
```

Or directly via Go:

```bash
cd server
go run ./cmd/agy-relay --public-host relay.example.com
```

Copy the printed `/dns4/relay.example.com/udp/4001/quic-v1/p2p/<RelayPeerID>` multiaddr. Open **4001/tcp** and **4001/udp** in your VPS firewall.

### 2. Run or Install Host Daemon (`agyd`) on Your PC / VPS

Foreground run:

```bash
cd server
go run ./cmd/agyd run \
  --workspace ~/dev/your-project \
  --relay /dns4/relay.example.com/udp/4001/quic-v1/p2p/<RelayPeerID>
```

Install as a persistent `systemd --user` background service:

```bash
cd server
go build -o ~/.local/bin/agyd ./cmd/agyd
~/.local/bin/agyd install-service \
  --workspace ~/dev/your-project \
  --relay /dns4/relay.example.com/udp/4001/quic-v1/p2p/<RelayPeerID>
sudo loginctl enable-linger $USER
```

Use `agyd install-service --dry-run ...` to preview the generated unit or `agyd uninstall-service` to remove it.

### 3. Pair Your Android Device

```bash
agyd pair
```

Open **Antigravity** on Android → **Hosts** → **+ Pair** → scan the terminal QR code (or paste the `agy://pair?...` URI / use Nearby LAN mDNS + PIN) → verify the 6-digit + emoji SAS code matches.

### 4. Build Native Bridge & Android `arm64-v8a` APK

```bash
./scripts/build_mobilebridge.sh
cd mobile
flutter build apk --release --target-platform android-arm64
```

Output APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`.

> Note: Building the AOT `--release` APK requires an `x86_64` Linux, macOS, or Windows host (or the included [`.github/workflows/release-apk.yml`](.github/workflows/release-apk.yml) GitHub Actions workflow on `ubuntu-latest`), because upstream Flutter does not ship a `linux-arm64/gen_snapshot` binary for `android-arm64-release`. On `linux/arm64` hosts, `flutter build apk --debug --target-platform android-arm64` builds natively.

For testing on an Android emulator behind nested NAT, launch the bundled relay + daemon + port forward script:

```bash
./scripts/run_emulator_stack.sh
```

Or forward manually with `adb reverse tcp:4001 tcp:4001`.

### 5. Android Release Signing (Optional)

Create `mobile/android/key.properties` alongside `mobile/android/release.jks`:

```properties
storeFile=release.jks
storePassword=<store-password>
keyAlias=<key-alias>
keyPassword=<key-password>
```

For CI releases via [.github/workflows/release-apk.yml](.github/workflows/release-apk.yml), set repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
