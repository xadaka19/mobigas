import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static const String _serverClientId =
      '370382275180-2qtg9vu294ad0oo21hv0rjt5i9mqv62c.apps.googleusercontent.com';

  static const String _androidClientId =
      '370382275180-0mb4shvv0sdlumbgtkh900i273buh0ss.apps.googleusercontent.com';

  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    debugPrint('GSI: initializing...');
    await _googleSignIn.initialize(
      clientId: _androidClientId,
      serverClientId: _serverClientId,
    );
    _initialized = true;
    debugPrint('GSI: initialized');
  }

  static Future<UserCredential?> signInWithGoogle() async {
    try {
      debugPrint('GSI: step 1 - ensure initialized');
      await _ensureInitialized();

      debugPrint('GSI: step 2 - calling authenticate()');
      final GoogleSignInAccount googleUser =
          await _googleSignIn.authenticate();

      debugPrint('GSI: step 3 - got user: ${googleUser.email}');
      final GoogleSignInAuthentication googleAuth =
          googleUser.authentication;

      debugPrint('GSI: step 4 - got auth, idToken null: ${googleAuth.idToken == null}');

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      debugPrint('GSI: step 5 - signing in with Firebase');
      final result = await FirebaseService.auth.signInWithCredential(credential);
      debugPrint('GSI: step 6 - Firebase sign in complete: ${result.user?.email}');
      return result;
    } catch (e, stack) {
      debugPrint('GSI ERROR: $e');
      debugPrint('GSI STACK: $stack');
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
