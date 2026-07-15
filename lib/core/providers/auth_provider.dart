import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/device_fingerprint_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/core/services/geo_service.dart';
import 'package:mobigas/core/services/google_auth_service.dart';
import 'package:mobigas/core/services/notification_service.dart';
import 'package:mobigas/core/services/storage_metadata.dart';
import 'package:mobigas/flavors/flavor_config.dart';

enum AuthState { unauthenticated, loading, authenticated }

class AuthProvider extends ChangeNotifier {
  // BUG FIX: used to default to `unauthenticated` — indistinguishable
  // from "confirmed logged out" to any splash/router logic checking
  // this value on the very first frame. On a fresh install, Firebase
  // Auth's silent session restore takes a real moment; starting in
  // `loading` means callers correctly wait instead of racing ahead.
  AuthState _state = AuthState.loading;
  CustomerModel? _customer;
  String? _error;

  /// True while register()/signInWithGoogle()/login() are running the
  /// explicit load path. Firebase fires authStateChanges the instant a
  /// credential lands, and the listener would race the explicit path —
  /// on signup, finding no profile doc yet and signing the user back
  /// out; on login, firing a SECOND redundant getUser() for the same
  /// users/{uid} doc over the same cold connection we're trying to keep
  /// fast. Suppressing the listener while an explicit path owns the
  /// load fixes both.
  bool _bootstrapping = false;

  /// Session-only dismissal of the home profile banner.
  bool _bannerDismissed = false;

  AuthState get state => _state;
  CustomerModel? get customer => _customer;
  String? get error => _error;
  bool get isAuthenticated => _state == AuthState.authenticated;

  AuthProvider() {
    // This provider manages the CUSTOMER profile (loads users/{uid}).
    // It lives in the shared widget tree (app.dart), so it also
    // instantiates in the VENDOR flavor — where it must stay inert. A
    // vendor has no users/{uid} document, so letting the listener run
    // there sends _loadCustomerWithRetry into ~4s of doomed Firestore
    // retries on every cold start, stalling vendor startup (the splash
    // hang). Vendor auth/data is handled by VendorProvider and the
    // vendor home screen, so bailing out here is safe.
    if (FlavorConfig.instance.flavor == FlavorType.vendor) {
      _state = AuthState.unauthenticated;
      return;
    }

    FirebaseService.auth.authStateChanges().listen((user) async {
      if (_bootstrapping) return;
      if (user == null) {
        _state = AuthState.unauthenticated;
        _customer = null;
        notifyListeners();
        return;
      }
      // Silent session restore on cold start. This is the path that
      // most often "takes forever" — the app reopens, Auth restores the
      // uid, and the user stares at the splash while a server round trip
      // fetches a profile that's already sitting in the local cache from
      // last run. allowCache lets us show that cached profile instantly
      // and refresh from the server in the background.
      await _loadCustomerWithRetry(user.uid, allowCache: true);
    });
  }

  // ---------------------------------------------------------------
  // Profile completion — drives the home onboarding banner.
  // These three steps used to live inside the 3-step signup wizard.
  // ---------------------------------------------------------------

  bool get hasPhone => (_customer?.phone ?? '').trim().isNotEmpty;

  bool get hasLocation =>
      (_customer?.latitude ?? 0) != 0 && (_customer?.longitude ?? 0) != 0;

  bool get hasVerification => (_customer?.nationalId ?? '').trim().isNotEmpty;

  /// Verification (step 3) is optional in v1, so "complete" only
  /// requires the two things an order actually cannot ship without.
  bool get isProfileComplete => hasPhone && hasLocation;

  int get profileStepsDone =>
      [hasPhone, hasLocation, hasVerification].where((done) => done).length;

  /// Index of the first step the customer still needs to do.
  int get firstIncompleteStep {
    if (!hasPhone) return 0;
    if (!hasLocation) return 1;
    return 2;
  }

  bool get showProfileBanner =>
      isAuthenticated &&
      _customer != null &&
      profileStepsDone < 3 &&
      !(_bannerDismissed && isProfileComplete);

  void dismissBanner() {
    _bannerDismissed = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------

  /// Loads the customer's Firestore profile after Firebase Auth
  /// confirms a signed-in user, retrying with backoff before giving
  /// up. A fresh install has no local Firestore cache yet, so the
  /// very first read after reinstall is genuinely slower and more
  /// failure-prone than normal — previously, a single transient
  /// failure here was treated identically to "this account was
  /// deleted, sign the user out".
  ///
  /// When [allowCache] is set (cold-start session restore), the first
  /// attempt reads from the local cache and, on a hit, authenticates
  /// immediately and kicks off a background server refresh. On a fresh
  /// install the cache is empty, that read throws, and we fall straight
  /// through to the normal server-backed path — so it's never slower
  /// than before, only faster when a cached profile exists.
  Future<void> _loadCustomerWithRetry(String uid,
      {int attempt = 0, bool allowCache = false}) async {
    const maxRetries = 3;

    if (allowCache && attempt == 0) {
      try {
        final cached =
            await FirestoreService.getUser(uid, source: Source.cache);
        if (cached != null) {
          // A cached users/{uid} doc only exists here because this
          // account already passed the vendor guard at a previous
          // login (a vendor can never be written into users/{uid} —
          // the guards in login()/signInWithGoogle() reject that), so
          // restoring it as an authenticated customer is safe without
          // re-running the guard on every cold start.
          _customer = cached;
          _state = AuthState.authenticated;
          _error = null;
          notifyListeners();
          unawaited(NotificationService.saveTokenForCurrentUser());
          // Catch up to any server-side changes since last run,
          // without making the user wait for it.
          unawaited(_refreshCustomerFromServer(uid));
          return;
        }
      } catch (_) {
        // Cold cache (fresh install / evicted) or a read error — fall
        // through to the server-backed load below.
      }
    }

    try {
      final customer = await FirestoreService.getUser(uid);
      if (customer != null) {
        _customer = customer;
        _state = AuthState.authenticated;
        _error = null;
        notifyListeners();
        // Token save (#1/#6): a signed-in session with a confirmed
        // profile is exactly when the FCM token must be on the
        // server. Covers silent session restore on cold start, where
        // the startup token save ran before auth had resolved.
        unawaited(NotificationService.saveTokenForCurrentUser());
        return;
      }
      if (attempt < 2) {
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        return _loadCustomerWithRetry(uid, attempt: attempt + 1);
      }
      _state = AuthState.unauthenticated;
      _customer = null;
      notifyListeners();
    } catch (e) {
      if (attempt < maxRetries) {
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        return _loadCustomerWithRetry(uid, attempt: attempt + 1);
      }
      _error = 'Could not load your profile. Check your connection.';
      // Deliberately NOT forcing unauthenticated — a connectivity
      // issue shouldn't look identical to "logged out".
      notifyListeners();
    }
  }

  /// Background-only refresh used after a cache hit. Reads from the
  /// server and updates the in-memory profile if it changed. Stays
  /// silent on failure — if we're offline, the cached profile the user
  /// is already looking at is the right thing to keep showing.
  Future<void> _refreshCustomerFromServer(String uid) async {
    try {
      final fresh = await FirestoreService.getUser(uid, source: Source.server);
      if (fresh != null && _state == AuthState.authenticated) {
        _customer = fresh;
        notifyListeners();
      }
    } catch (_) {
      // Offline / transient — keep the cached profile on screen.
    }
  }

  // ---------------------------------------------------------------
  // Email / password
  // ---------------------------------------------------------------

  Future<void> login(String email, String password) async {
    _state = AuthState.loading;
    _error = null;
    // Own the load path so the authStateChanges listener doesn't fire a
    // second, parallel getUser() for the same doc over the cold
    // connection. Reset in finally.
    _bootstrapping = true;
    notifyListeners();

    try {
      final credential = await FirebaseService.auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final uid = credential.user!.uid;

      // PARALLELISM: the vendor guard and the profile read are two
      // independent single-doc reads. On a cold connection they used to
      // be awaited one after the other — two full round trips stacked
      // on top of the auth handshake. Start the profile read now so it
      // runs DURING the vendor round trip. The vendor guard is still
      // awaited on its own and stays authoritative: if it fails or says
      // "vendor", we never look at the profile.
      final profileFuture = FirestoreService.getUser(uid);

      final bool isVendor;
      try {
        // SECURITY GUARD: this uid may belong to a vendor account
        // (vendor credentials typed into the customer app, or an
        // email/password reused across both flows). Nothing downstream
        // stops an authenticated user from reaching customer screens
        // regardless of account type — so the check happens here,
        // before the caller is ever treated as a customer. On a read
        // error we fail closed (never skip the guard) and let the user
        // retry rather than risk letting a vendor through.
        isVendor = await FirestoreService.isRegisteredVendor(uid);
      } catch (_) {
        unawaited(profileFuture.catchError((_) => null));
        _error = 'No internet connection';
        _state = AuthState.unauthenticated;
        return;
      }

      if (isVendor) {
        unawaited(profileFuture.catchError((_) => null));
        await GoogleAuthService.signOut();
        _error = 'This account is registered as a MobiGas vendor. '
            'Please use the MobiGas Vendor app to sign in.';
        _state = AuthState.unauthenticated;
        return;
      }

      CustomerModel? customer;
      try {
        customer = await profileFuture;
      } catch (_) {
        // The profile read specifically failed (offline / transient).
        // Surface it fast instead of sitting through the long backoff —
        // the user can just tap "Sign in" again.
        _error = 'Could not load your profile. Check your connection.';
        _state = AuthState.unauthenticated;
        return;
      }

      if (customer == null) {
        // Auth succeeded but the profile doc isn't visible yet — a rare
        // propagation edge. One short retry, not the full backoff.
        await Future.delayed(const Duration(milliseconds: 600));
        try {
          customer = await FirestoreService.getUser(uid);
        } catch (_) {
          // fall through to the null handling below
        }
      }

      if (customer != null) {
        _customer = customer;
        _state = AuthState.authenticated;
        _error = null;
        unawaited(NotificationService.saveTokenForCurrentUser());
      } else {
        _error = 'Could not load your profile. Check your connection.';
        _state = AuthState.unauthenticated;
      }
    } on FirebaseAuthException catch (e) {
      _error = _authError(e.code);
      _state = AuthState.unauthenticated;
    } finally {
      _bootstrapping = false;
      notifyListeners();
    }
  }

  /// Minimal signup. Everything the customer can add later — phone,
  /// delivery location, National ID, photo — is deferred to the home
  /// profile banner so nothing stands between "I want gas" and the
  /// vendor list.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    String phone = '',
    File? selfieFile,
    String nationalId = '',
    String county = '',
    String area = '',
    String estate = '',
    double latitude = 0,
    double longitude = 0,
    String? referralCode,
  }) async {
    _state = AuthState.loading;
    _error = null;
    _bootstrapping = true;
    notifyListeners();

    try {
      final deviceFingerprint = await DeviceFingerprintService.getFingerprint();

      // Only run the duplicate guard on values the customer actually
      // supplied. A blank phone or blank ID can never be "taken", and
      // querying on '' would match every other incomplete profile.
      var deviceFlagged = false;
      if (phone.trim().isNotEmpty || nationalId.trim().isNotEmpty) {
        final duplicates = await FirestoreService.checkDuplicates(
          phone: phone.trim(),
          nationalId: nationalId.trim(),
          deviceFingerprint: deviceFingerprint,
        );
        deviceFlagged = duplicates['deviceFlagged'] ?? false;

        if (phone.trim().isNotEmpty && duplicates['phoneTaken'] == true) {
          _error = 'An account already exists with this phone number. '
              'Please sign in instead.';
          _state = AuthState.unauthenticated;
          return;
        }
        if (nationalId.trim().isNotEmpty && duplicates['idTaken'] == true) {
          _error = 'An account already exists with this National ID. '
              'Please sign in instead.';
          _state = AuthState.unauthenticated;
          return;
        }
      }

      final credential =
          await FirebaseService.auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final uid = credential.user!.uid;

      // register() almost never receives real coordinates — location
      // collection moved to the home profile banner (saveLocation
      // below) — so this only fires on the rare caller that already
      // has a pin. GeoService falls back gracefully to 'KE' via the
      // CustomerModel default when latitude/longitude are still 0.
      final detectedCountry = (latitude != 0 || longitude != 0)
          ? (GeoService.countryFromLatLng(latitude, longitude) ?? 'KE')
          : 'KE';

      final customer = CustomerModel(
        id: uid,
        name: name.trim(),
        email: email.trim().toLowerCase(),
        phone: phone.trim(),
        deviceFingerprint: deviceFingerprint,
        deviceFlagged: deviceFlagged,
        nationalId: nationalId.trim(),
        county: county,
        area: area,
        estate: estate,
        country: detectedCountry,
        latitude: latitude,
        longitude: longitude,
      );

      final selfieUploadFuture = selfieFile == null
          ? Future<String?>.value(null)
          : (() async {
              final ref =
                  FirebaseStorage.instance.ref().child('selfies').child(uid);
              await ref.putFile(selfieFile, imageMetadata(selfieFile));
              return ref.getDownloadURL();
            })();

      // #6: authMethod folded into the create — one write instead of
      // two (createUser + a separate update just to set authMethod).
      await FirestoreService.createUser(customer, authMethod: 'password');

      final selfieUrl = await selfieUploadFuture;
      if (selfieUrl != null) {
        await FirebaseService.users.doc(uid).update({'selfieUrl': selfieUrl});
      }

      if (referralCode != null && referralCode.trim().isNotEmpty) {
        try {
          await FirestoreService.recordReferralSignup(
            code: referralCode.trim(),
            referredType: 'customer',
            deviceFingerprint: deviceFingerprint,
          );
        } catch (_) {
          // Don't let a referral hiccup block a successful signup.
        }
      }

      // #6: skip the final re-read when there's no selfie — we already
      // hold the object we just wrote. Only re-read when a selfieUrl
      // was written after createUser, so the local copy reflects it.
      _customer = selfieUrl != null
          ? (await FirestoreService.getUser(uid) ?? customer)
          : customer;
      _state = AuthState.authenticated;
      // #1/#6: profile doc provably exists now — safe moment to
      // persist the FCM token for a brand-new account, closing the
      // race the auth listener alone can't cover.
      unawaited(NotificationService.saveTokenForCurrentUser());
    } on FirebaseAuthException catch (e) {
      _error = _authError(e.code);
      _state = AuthState.unauthenticated;
    } catch (e) {
      _error = 'Could not create your account. Please try again.';
      _state = AuthState.unauthenticated;
    } finally {
      _bootstrapping = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------
  // Google
  // ---------------------------------------------------------------

  /// One button for both signup and login: if there's no Firestore
  /// profile for this Google account yet, we create one from the
  /// Google identity and let the home banner collect the rest.
  Future<bool> signInWithGoogle() async {
    _state = AuthState.loading;
    _error = null;
    _bootstrapping = true;
    notifyListeners();

    try {
      final credential = await GoogleAuthService.signInWithGoogle();
      if (credential == null) {
        _error = 'Google sign-in did not complete. Please try again.';
        _state = AuthState.unauthenticated;
        return false;
      }

      final user = credential.user!;

      // SECURITY GUARD: must run BEFORE the "no profile yet -> create
      // one" branch below. Without this, a vendor's Google account
      // signing in here for the first time would silently get a
      // brand-new customer profile created on the SAME uid — quietly
      // turning a vendor's identity into a customer account instead
      // of rejecting the sign-in.
      final isVendor = await FirestoreService.isRegisteredVendor(user.uid);
      if (isVendor) {
        await GoogleAuthService.signOut();
        _error = 'This Google account is registered as a MobiGas vendor. '
            'Please use the MobiGas Vendor app to sign in.';
        _state = AuthState.unauthenticated;
        return false;
      }

      final existing = await FirestoreService.getUser(user.uid);

      if (existing != null) {
        _customer = existing;
        _state = AuthState.authenticated;
        // #1/#6: existing Google user just authenticated — persist token.
        unawaited(NotificationService.saveTokenForCurrentUser());
        return true;
      }

      final deviceFingerprint = await DeviceFingerprintService.getFingerprint();
      final displayName = (user.displayName ?? '').trim();

      final customer = CustomerModel(
        id: user.uid,
        name: displayName.isEmpty ? 'MobiGas customer' : displayName,
        email: (user.email ?? '').trim().toLowerCase(),
        phone: user.phoneNumber ?? '',
        deviceFingerprint: deviceFingerprint,
        deviceFlagged: false,
        nationalId: '',
        county: '',
        area: '',
        estate: '',
        // No pin yet — Google sign-up's CompleteProfileScreen (or the
        // home banner) collects location afterward, same as
        // saveLocation() does for password accounts. Country stays
        // at the CustomerModel default ('KE') until then.
        latitude: 0,
        longitude: 0,
      );

      // authMethod + optional photo are google-specific; the photo is
      // only known here, so this branch keeps its single follow-up
      // update rather than folding into createUser.
      await FirestoreService.createUser(customer);
      await FirebaseService.users.doc(user.uid).update({
        'authMethod': 'google',
        if ((user.photoURL ?? '').isNotEmpty) 'selfieUrl': user.photoURL,
      });

      // Re-read here because the google branch wrote selfieUrl (photo)
      // after createUser, and we want the local copy to reflect it.
      _customer = await FirestoreService.getUser(user.uid) ?? customer;
      _state = AuthState.authenticated;
      // #1/#6: new Google account — doc now exists, persist token.
      unawaited(NotificationService.saveTokenForCurrentUser());
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _authError(e.code);
      _state = AuthState.unauthenticated;
      return false;
    } catch (e) {
      _error = 'Could not sign in with Google. Please try again.';
      _state = AuthState.unauthenticated;
      return false;
    } finally {
      _bootstrapping = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------
  // Deferred profile steps (called from the home banner)
  // Each returns null on success, or an error string to show.
  // ---------------------------------------------------------------

  Future<String?> savePhone(String phone) async {
    final uid = _customer?.id;
    if (uid == null) return 'You are not signed in.';

    final clean = phone.trim();
    if (clean.length < 9) return 'Enter a valid phone number.';

    try {
      final deviceFingerprint = await DeviceFingerprintService.getFingerprint();
      final duplicates = await FirestoreService.checkDuplicates(
        phone: clean,
        nationalId: '',
        deviceFingerprint: deviceFingerprint,
      );
      // Guard only matters while this profile's own phone is blank —
      // which is exactly when this step runs.
      if (duplicates['phoneTaken'] == true && !hasPhone) {
        return 'Another account already uses this phone number.';
      }

      await FirebaseService.users.doc(uid).update({'phone': clean});
      await refreshCustomer();
      return null;
    } catch (e) {
      return 'Could not save your phone number. Check your connection.';
    }
  }

  /// Called from ProfileCompletionSheet's location step. This is the
  /// FIRST time most customers ever have a real GPS pin, so it's also
  /// where country gets decided — same GeoService detection
  /// vendor_setup_screen.dart uses at vendor onboarding, applied here
  /// for the customer side. Falls back to whatever the customer
  /// already had (or 'KE') if the pin falls outside every supported
  /// market, rather than leaving country unset.
  Future<String?> saveLocation({
    required String area,
    required double latitude,
    required double longitude,
  }) async {
    final uid = _customer?.id;
    if (uid == null) return 'You are not signed in.';
    if (latitude == 0 || longitude == 0) {
      return 'Pin your exact location on the map.';
    }

    try {
      final detectedCountry = GeoService.countryFromLatLng(
            latitude,
            longitude,
          ) ??
          _customer?.country ??
          'KE';

      await FirebaseService.users.doc(uid).update({
        'county': area.trim(),
        'area': area.trim(),
        'estate': area.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'country': detectedCountry,
      });
      await refreshCustomer();
      return null;
    } catch (e) {
      return 'Could not save your location. Check your connection.';
    }
  }

  Future<String?> saveVerification({String? nationalId, File? selfie}) async {
    final uid = _customer?.id;
    if (uid == null) return 'You are not signed in.';

    final data = <String, dynamic>{};
    final id = (nationalId ?? '').trim();
    if (id.isNotEmpty) {
      if (id.length < 7) return 'Enter a valid National ID number.';
      data['nationalId'] = id;
    }

    try {
      if (selfie != null) {
        final ref =
            FirebaseStorage.instance.ref().child('selfies').child(uid);
        await ref.putFile(selfie, imageMetadata(selfie));
        data['selfieUrl'] = await ref.getDownloadURL();
      }
      if (data.isEmpty) return null;

      await FirebaseService.users.doc(uid).update(data);
      await refreshCustomer();
      return null;
    } catch (e) {
      return 'Could not save your details. Check your connection.';
    }
  }

  // ---------------------------------------------------------------

  Future<void> resetPassword(String email) async {
    await FirebaseService.auth.sendPasswordResetEmail(email: email);
  }

  Future<void> refreshCustomer() async {
    if (_customer == null) return;
    final updated = await FirestoreService.getUser(_customer!.id);
    if (updated != null) {
      _customer = updated;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    // Signs out of Google *and* Firebase. Harmless for password
    // accounts that never touched Google.
    await GoogleAuthService.signOut();
    _state = AuthState.unauthenticated;
    _customer = null;
    _bannerDismissed = false;
    notifyListeners();
  }

  String _authError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password';
      case 'invalid-email':
        return 'That email address is not valid';
      case 'email-already-in-use':
        return 'An account already exists with this email';
      case 'account-exists-with-different-credential':
        return 'This email is already registered. Sign in with your password.';
      case 'weak-password':
        return 'Password must be at least 6 characters';
      case 'too-many-requests':
        return 'Too many attempts. Wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}