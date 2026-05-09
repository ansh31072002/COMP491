# SECURELY — User Guide

**Who this is for:** anyone who needs to run the project and try it out.

**What SECURELY is:** A secure chat app (Flutter + Firebase). You can sign up, log in with MFA, send encrypted messages in 1:1 and group chats, search users, and if you’re a manager you get an admin panel to manage users and roles. Right now it runs in the browser; mobile could be added later.

---

## Getting it running

1. **Flutter** — Install from [flutter.dev](https://flutter.dev), put it on your PATH, run `flutter doctor` and fix whatever it complains about (e.g. Chrome for web).

2. **Open the project** — Open the project folder in your editor/terminal.

3. **Dependencies** — In the project root:
   ```bash
   flutter pub get
   ```

4. **Firebase** — App uses Firebase for auth and Firestore. There should be a `lib/firebase_options.dart` in the repo. If it’s missing or you get Firebase errors, run:
   ```bash
   flutterfire configure
   ```
   and hook it up to your Firebase project.

5. **Run it** — For web:
   ```bash
   flutter run -d chrome
   ```
   Or run `flutter run` and pick a device.

---

## Basic flow: login and send a message

1. Start the app — you see the login screen.
2. If you don’t have an account: switch to Register, fill in name, phone, role (Employee/Manager), email, password (6+ chars), finish signup. You might do MFA setup here.
3. Log in with email/password. When it asks for MFA, pick Email or SMS and enter the 6-digit code. You land on the home screen (Chats / Groups).
4. Search for another user at the top, tap them to open a chat, type a message and send. It’s encrypted before it’s stored; the other person sees it decrypted in their chat.
5. Optional: tap the + on the home screen to create a group (name, description, add people), then open it and chat the same way.

---

## Where things show up

- **In the app:** Chats/groups list on home. Open a chat to see the thread; your messages on one side, theirs on the other. In the list, the last message might show “[Encrypted Message]” — the real text only shows inside the chat. Managers can open the menu and go to Admin Panel to see users and change roles.
- **Terminal:** `flutter run` logs everything there; errors (Firebase, encryption, etc.) show up as red text or stack traces.
- **Browser:** On web, in-app errors usually show as Snackbars or popups.

---

## Troubleshooting

**Firebase errors / no `firebase_options.dart`**  
Run `flutterfire configure` in the project root and pick your Firebase project (and at least web). If you don’t have a project yet, create one at [console.firebase.google.com](https://console.firebase.google.com), then run `flutterfire configure` again.

**“No devices” or Chrome not found**  
You need Chrome for web. Run `flutter doctor` and fix the Chrome line. Use `flutter run -d chrome` to target web. On a headless machine you can do `flutter run -d web-server` and open the URL it prints.

---

For more detail on what the app does and how security works, see the code in `lib/` and the API doc in `docs/api.md`.
