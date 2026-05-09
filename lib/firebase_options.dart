// Firebase configuration for college project
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD0m-fnhc_qDxtGGQzu99Y78sklniq4_sY',
    appId: '1:195753331141:web:a5685cac06ad18a05e23ac',
    messagingSenderId: '195753331141',
    projectId: 'secure-chat-app-2024',
    authDomain: 'chat-app-2024-7f975.firebaseapp.com',
    storageBucket: 'secure-chat-app-2024.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAEQXXNE8v4YBo05ejasvE7ogQUMwKGMMY',
    appId: '1:195753331141:android:27678f5908f57e9d5e23ac',
    messagingSenderId: '195753331141',
    projectId: 'secure-chat-app-2024',
    storageBucket: 'secure-chat-app-2024.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDVmtWqqKxQrx48dziMN6GZLGI8YNWWIgQ',
    appId: '1:754765338477:ios:your-ios-app-id',
    messagingSenderId: '754765338477',
    projectId: 'secure-chat-app-2024',
    storageBucket: 'secure-chat-app-2024.firebasestorage.app',
    iosBundleId: 'com.example.secureChatApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDVmtWqqKxQrx48dziMN6GZLGI8YNWWIgQ',
    appId: '1:754765338477:ios:your-macos-app-id',
    messagingSenderId: '754765338477',
    projectId: 'secure-chat-app-2024',
    storageBucket: 'secure-chat-app-2024.firebasestorage.app',
    iosBundleId: 'com.example.secureChatApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDVmtWqqKxQrx48dziMN6GZLGI8YNWWIgQ',
    appId: '1:754765338477:web:c923bd7788e1dacba0ec64',
    messagingSenderId: '754765338477',
    projectId: 'ly-66789',
    authDomain: 'ly-66789.firebaseapp.com',
    storageBucket: 'ly-66789.appspot.com',
  );
}
