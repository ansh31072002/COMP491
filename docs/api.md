# API Documentation

## encryptMessage (EncryptionService)

**What it does:** Takes a normal string and encrypts it with AES-256 so you can store or send it safely. Only people with the right key can decrypt it. We use this for every chat message (1:1 and groups).

**Signature:**
```dart
static String encryptMessage(String message, String keyString)
```

**Parameters:**

| Name        | Type   | Description |
|-------------|--------|-------------|
| message     | String | The text you want to encrypt. Any length is fine. |
| keyString   | String | The key in base64 (from `generateRandomKey()` or `getSharedKey(chatId)`). Has to be 32 bytes when decoded. |

**Returns:** A single base64 string: first 16 bytes are a random IV, then the encrypted stuff. If something goes wrong or either param is empty, you get the original `message` back (so nothing blows up).

**What can go wrong:**
- Bad or wrong-length key — we catch it and return the plain message, and print "AES Encryption error" to the console.
- Empty message or key — we just return the message. No exceptions thrown.

**Quick example:**
```dart
import 'package:secure_chat_app/services/encryption_service.dart';

// get the shared key for this chat
String key = await EncryptionService.getOrCreateSharedKey('chat_abc123');

String plain = "Hello, this is secret!";
String cipher = EncryptionService.encryptMessage(plain, key);
// send/store cipher, not plain

// other side decrypts with same key
String decrypted = EncryptionService.decryptMessage(cipher, key);
```

**decryptMessage** does the opposite — same key, pass in the encrypted string:
```dart
static String decryptMessage(String encryptedData, String keyString)  // returns String
```
If decryption fails (wrong key, bad data) it just gives you back `encryptedData` unchanged.

**Notes:**
- Key has to be base64 and 32 bytes. Use `generateRandomKey()` when you need a new one.
- We use a new random IV every time, so the same message encrypted twice looks different (which is what you want).
- On error we return the original string instead of throwing — so don’t assume “same string in/out” means it wasn’t encrypted when it’s sensitive stuff.
- In the app, chat screens get the key via `getOrCreateSharedKey(chatId)`, then encrypt before saving to Firestore and decrypt when loading.
