import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // Web client ID (type 3) — needed for serverClientId
  static const String _serverClientId =
      '370382275180-2qtg9vu294ad0oo21hv0rjt5i9mqv62c.apps.googleusercontent.com';

  // Android client ID (type 1) — needed for clientId on Android
  static const String _androidClientId =
      '370382275180-0mb4shvv0sdlumbgtkh900i273buh0ss.apps.googleusercontent.com';

  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.initialize(
      clientId: _androidClientId,
      serverClientId: _serverClientId,
    );
    _initialized = true;
  }

  static Future<UserCredential?> signInWithGoogle() async {
    try {
      await _ensureInitialized();

      final GoogleSignInAccount googleUser =
          await _googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth =
          googleUser.authentication;

      debugPrint('idToken: ${googleAuth.idToken}');

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      return await FirebaseService.auth.signInWithCredential(credential);
    } catch (e, stack) {
      debugPrint('Google Sign-In error: $e');
      debugPrint('Stack: $stack');
      return null;
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await FirebaseService.auth.signOut();
  }

  static String? get currentUserEmail =>
      FirebaseService.auth.currentUser?.email;

  static String? get currentUserName =>
      FirebaseService.auth.currentUser?.displayName;

  static String? get currentUserPhoto =>
      FirebaseService.auth.currentUser?.photoURL;
}
