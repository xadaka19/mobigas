import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mobigas/core/services/firebase_service.dart';

/// Shared by the customer (com.mobigas.mobigas) and vendor
/// (com.mobigas.vendor) flavors.
///
/// On Android the app is identified by its package name + SHA-1
/// signing certificate, both registered in the Firebase console. The
/// Android OAuth client ID is never passed from Dart — `clientId` is
/// an iOS/Web parameter and is ignored on Android. All Android needs
/// is the project's *web* OAuth client (`client_type: 3` in
/// google-services.json), which is what mints the idToken Firebase
/// verifies.
class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  /// Web OAuth client for mobigas-prod. Project-wide, not per-flavor.
  /// Passed explicitly so a mis-merged google-services.json fails
  /// loudly at the Firebase layer rather than silently here.
  static const String _serverClientId =
      '370382275180-2qtg9vu294ad0oo21hv0rjt5i9mqv62c.apps.googleusercontent.com';

  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.initialize(serverClientId: _serverClientId);
    _initialized = true;
  }

  static Future<UserCredential?> signInWithGoogle() async {
    try {
      await _ensureInitialized();

      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      if (googleAuth.idToken == null) {
        // Almost always a signing-certificate mismatch: the SHA-1 of
        // the running build is not registered against this package
        // name in Firebase. Most common cause is a Play-signed
        // install whose App Signing SHA-1 was never added.
        debugPrint('GSI: no idToken — check SHA-1 registration for '
            'this package name in the Firebase console.');
        return null;
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      return await FirebaseService.auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      // clientConfigurationError => google-services.json is missing a
      // web OAuth client, or the Gradle plugin didn't run.
      debugPrint('GSI ERROR [${e.code}]: ${e.description}');
      return null;
    } catch (e, stack) {
      debugPrint('GSI ERROR: $e');
      debugPrint('GSI STACK: $stack');
      return null;
    }
  }

  /// Silent sign-in for returning users. Returns null when there is
  /// no cached credential — callers should treat that as "show the
  /// sign-in screen", not as an error.
  static Future<UserCredential?> signInSilently() async {
    try {
      await _ensureInitialized();
      final future = _googleSignIn.attemptLightweightAuthentication();
      if (future == null) return null;

      final googleUser = await future;
      if (googleUser == null) return null;

      final googleAuth = googleUser.authentication;
      if (googleAuth.idToken == null) return null;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      return await FirebaseService.auth.signInWithCredential(credential);
    } catch (e) {
      return null;
    }
  }

  static Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await _googleSignIn.signOut();
    } catch (_) {
      // A password-only account never touched Google — don't let this
      // block the Firebase sign-out below.
    }
    await FirebaseService.auth.signOut();
  }

  static String? get currentUserEmail =>
      FirebaseService.auth.currentUser?.email;
  static String? get currentUserName =>
      FirebaseService.auth.currentUser?.displayName;
  static String? get currentUserPhoto =>
      FirebaseService.auth.currentUser?.photoURL;
}