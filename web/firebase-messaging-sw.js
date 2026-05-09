// Firebase Cloud Messaging service worker for SECURELY (web)

importScripts('https://www.gstatic.com/firebasejs/10.12.4/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.4/firebase-messaging-compat.js');

// Firebase config for web – taken from firebase_options.dart
firebase.initializeApp({
  apiKey: "AIzaSyD0m-fnhc_qDxtGGQzu99Y78sklniq4_sY",
  appId: "1:195753331141:web:a5685cac06ad18a05e23ac",
  messagingSenderId: "195753331141",
  projectId: "secure-chat-app-2024",
  authDomain: "chat-app-2024-7f975.firebaseapp.com",
  storageBucket: "secure-chat-app-2024.firebasestorage.app",
});

const messaging = firebase.messaging();

// Handle background messages when the web app is not in the foreground.
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);

  const notificationTitle = payload.notification?.title || 'SECURELY';
  const notificationOptions = {
    body: payload.notification?.body || 'You have a new message.',
    // icon: '/icons/Icon-192.png', // Optional: add if you have an icon
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});

