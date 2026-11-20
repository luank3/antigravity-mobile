# Contributing to Antigravity Mobile

Thank you for your interest in contributing to Antigravity Mobile! We welcome bug reports, feature requests, documentation improvements, and code contributions.

## Code of Conduct

Please treat everyone with respect, kindness, and professionalism.

## Repository Layout

- `mobile/`: Flutter (Android `arm64-v8a`) client application.
- `server/`: Go daemon (`agyd`), self-hosted Circuit Relay v2 (`agy-relay`), and C-shared mobile bridge (`server/pkg/mobilebridge`).
- `deploy/relay/`: Production Docker and Docker Compose assets for `agy-relay`.
- `scripts/`: Development and helper scripts (building native bridges, emulator stacks).
- `docs/`: Architecture designs, technical specifications, and plans.

## Development Workflow

### Prerequisites

- **Go**: 1.26 or newer (with CGO enabled for `mobilebridge`).
- **Flutter**: 3.47.x (tested on 3.47.9).
- **Android SDK & NDK**: NDK 28.2.13676358 or compatible.
- **Git**

### Running Tests Locally

Before submitting PRs or commits, ensure all tests pass:

1. **Go Server & Relay Tests**:
   ```bash
   cd server
   go test -count=1 ./... -race
   ```

2. **Flutter Analyzer & Tests**:
   ```bash
   cd mobile
   flutter analyze
   flutter test -r expanded test/widget_test.dart
   ```

### Building the Mobile Bridge (`libagyp2p.so`)

To build the native bridge for Android `arm64-v8a`:

```bash
export ANDROID_NDK_ROOT="/path/to/android-sdk/ndk/28.2.13676358"
./scripts/build_mobilebridge.sh
```

### Commit Guidelines

We use conventional commit messages to keep history clean and structured:

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation updates
- `ci:` CI/CD pipeline changes
- `refactor:` Code improvements without behavioral changes
- `chore:` Miscellaneous tasks

### Pull Requests

1. Fork the repository and create your feature branch from `main`.
2. Keep your branch focused on a single topic.
3. Verify that all tests pass locally.
4. Push your commits and open a Pull Request against `main`.
