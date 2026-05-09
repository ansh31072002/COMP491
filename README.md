# SECURELY (COMP491)

SECURELY is a Flutter + Firebase secure messaging app with:
- email/password and Google sign-in
- MFA flows
- encrypted chat messages
- one-to-one and group chat
- voice/video calling

## Repository Contents

- **Source code**: `lib/`, `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`
- **Project docs**: `docs/`
- **Build instructions**: this file
- **Deployment instructions**: `DEPLOY.md`
- **Configuration templates**: `.env.example`, `docker-compose.yml`

## Prerequisites

- Flutter SDK (3.9+ recommended)
- Dart SDK (bundled with Flutter)
- Chrome (for web run)
- Firebase project with Auth + Firestore enabled

## Setup

1. Clone and open the project.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Copy the environment template:
   ```bash
   cp .env.example .env
   ```
4. Configure Firebase (if needed) and verify `lib/firebase_options.dart` is valid for your project.
5. If running with Firebase emulators, see `docker-compose.yml`.

## Build Instructions

### Debug (web)
```bash
flutter run -d chrome
```

### Production web build
```bash
flutter build web --release
```

### Android APK
```bash
flutter build apk --release
```

### iOS (macOS only)
```bash
flutter build ios --release
```

## Execution

- Start app locally:
  ```bash
  flutter run
  ```
- Select target device (Chrome/mobile/emulator) when prompted.

## Validation / Verification

Run these checks before release:

```bash
flutter analyze
flutter test
```

Manual validation checklist:
- user can sign up and log in
- MFA challenge can be completed
- user can send/receive messages
- group chat can be created and used
- call UI can be initiated

## Branching and Versioning Model

- `main`: stable, release-ready branch
- `dev`: integration branch for ongoing feature work

Recommended flow:
1. branch from `dev` using `feature/<name>`
2. merge feature branch into `dev`
3. merge `dev` into `main` for release

Versioning:
- Use semantic versioning (`MAJOR.MINOR.PATCH`)
- Update `version` in `pubspec.yaml` for each release

## Optional Release Artifacts

Generated artifacts are optional and typically not committed:
- `build/web/`
- Android release APK/AAB
- iOS archive outputs

If required for class submission, publish artifacts through GitHub Releases.
