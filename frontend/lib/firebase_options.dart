// FILE: lib/firebase_options.dart
//
// IMPORTANT: Replace all placeholder values below with the actual values from
// your Firebase project console.
//
// How to get these values:
//   1. Go to https://console.firebase.google.com
//   2. Open your project → Project Settings → General
//   3. Scroll to "Your apps" → Web app → SDK setup and configuration
//   4. Copy each field below
//
// For the full FlutterFire CLI approach:
//   flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID

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
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyALcAaeI8EYp7znY1mslBy-u__aygi3hIY',
    appId: '1:868951173690:web:1324ca73f03b4d813b2303',
    messagingSenderId: '868951173690',
    projectId: 'fairhire-6b3d4',
    authDomain: 'fairhire-6b3d4.firebaseapp.com',
    storageBucket: 'fairhire-6b3d4.firebasestorage.app',
    measurementId: 'G-HLRT8CPP0E',
  );

  // ── Web ───────────────────────────────────────────────────────────────────

  // ── Android ───────────────────────────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_FIREBASE_PROJECT_ID',
    storageBucket: 'YOUR_FIREBASE_PROJECT_ID.appspot.com',
  );

  // ── iOS ───────────────────────────────────────────────────────────────────
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_FIREBASE_PROJECT_ID',
    storageBucket: 'YOUR_FIREBASE_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.fairhire',
  );

  // ── macOS ─────────────────────────────────────────────────────────────────
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: 'YOUR_MACOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_FIREBASE_PROJECT_ID',
    storageBucket: 'YOUR_FIREBASE_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.fairhire',
  );
}