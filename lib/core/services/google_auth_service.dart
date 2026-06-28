import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static const String _serverClientId =
      '370382275180-2qtg9vu294ad0oo21hv0rjt5i9mqv62c.apps.googleusercontent.com';

  static Future<UserCredential?> signInWithGoogle() async {
    try {
      await _googleSignIn.initialize(
        serverClientId: _serverClientId,
      );
      final GoogleSignInAccount googleUser =
          await _googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth =
          googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      return await FirebaseService.auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
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
