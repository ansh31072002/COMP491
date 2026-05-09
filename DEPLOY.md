# Deployment Guide

This document describes how to deploy SECURELY for web and mobile targets.

## 1) Pre-Deployment Checklist

- `flutter analyze` passes
- `flutter test` passes
- Firebase project is configured (Auth + Firestore)
- `lib/firebase_options.dart` matches target Firebase project
- Secrets are set in runtime config (do not hardcode secrets)

## 2) Web Deployment

### Build
```bash
flutter build web --release
```

Output is created in:
- `build/web/`

### Deploy to Firebase Hosting (example)
1. Install Firebase CLI.
2. Login:
   ```bash
   firebase login
   ```
3. Deploy:
   ```bash
   firebase deploy --only hosting
   ```

## 3) Android Deployment

### Build release APK
```bash
flutter build apk --release
```

### Build App Bundle
```bash
flutter build appbundle --release
```

Sign using your Android keystore before Play Store upload.

## 4) iOS Deployment (macOS only)

```bash
flutter build ios --release
```

Then archive and distribute through Xcode / App Store Connect.

## 5) Environment and Configuration

- Use `.env.example` as template for runtime configuration.
- Keep production secrets outside git (CI/CD secret store or hosting platform settings).
- Confirm Firebase keys/IDs are pointed to the correct environment (dev vs prod).

## 6) Recommended CI/CD Steps

1. Checkout `main`
2. `flutter pub get`
3. `flutter analyze`
4. `flutter test`
5. Build target (`web`, `apk`, or `ios`)
6. Deploy artifacts

## 7) Rollback

- Re-deploy last known good artifact from CI/CD history.
- Revert to previous release tag and redeploy.
