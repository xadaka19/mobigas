import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/device_fingerprint_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/core/services/google_auth_service.dart';
import 'package:mobigas/core/services/storage_metadata.dart';

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

  /// True while register()/signInWithGoogle() are creating the
  /// Firestore profile for a brand-new account. Firebase fires
  /// authStateChanges the instant the credential lands — before the
  /// profile document exists — and the listener would race ahead,
  /// find nothing, and sign the user straight back out. Suppress it
  /// until the writing path has finished and set state itself.
  bool _bootstrapping = false;

  /// Session-only dismissal of the home profile banner.
  bool _bannerDismissed = false;

  AuthState get state => _state;
  CustomerModel? get customer => _customer;
  String? get error => _error;
  bool get isAuthenticated => _state == AuthState.authenticated;

  AuthProvider() {
    FirebaseService.auth.authStateChanges().listen((user) async {
      if (_bootstrapping) return;
      if (user == null) {
        _state = AuthState.unauthenticated;
        _customer = null;
        notifyListeners();
        return;
      }
      await _loadCustomerWithRetry(user.uid);
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
  Future<void> _loadCustomerWithRetry(String uid, {int attempt = 0}) async {
    const maxRetries = 3;
    try {
      final customer = await FirestoreService.getUser(uid);
      if (customer != null) {
        _customer = customer;
        _state = AuthState.authenticated;
        _error = null;
        notifyListeners();
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

  // ---------------------------------------------------------------
  // Email / password
  // ---------------------------------------------------------------

  Future<void> login(String email, String password) async {
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    try {
      final credential = await FirebaseService.auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      await _loadCustomerWithRetry(credential.user!.uid);
    } on FirebaseAuthException catch (e) {
      _error = _authError(e.code);
      _state = AuthState.unauthenticated;
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
    List<GuarantorModel> guarantors = const [],
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
        latitude: latitude,
        longitude: longitude,
        bankApprovedLimit: null,
        bankCreditUsed: 0,
        bankStatus: BankApprovalStatus.pending,
        partnerBankName: '',
        guarantors: guarantors,
      );

      final selfieUploadFuture = selfieFile == null
          ? Future<String?>.value(null)
          : (() async {
              final ref =
                  FirebaseStorage.instance.ref().child('selfies').child(uid);
              await ref.putFile(selfieFile, imageMetadata(selfieFile));
              return ref.getDownloadURL();
            })();

      await FirestoreService.createUser(customer);
      await FirebaseService.users.doc(uid).update({'authMethod': 'password'});

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

      _customer = await FirestoreService.getUser(uid) ?? customer;
      _state = AuthState.authenticated;
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
      final existing = await FirestoreService.getUser(user.uid);

      if (existing != null) {
        _customer = existing;
        _state = AuthState.authenticated;
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
        latitude: 0,
        longitude: 0,
        bankApprovedLimit: null,
        bankCreditUsed: 0,
        bankStatus: BankApprovalStatus.pending,
        partnerBankName: '',
        guarantors: const [],
      );

      await FirestoreService.createUser(customer);
      await FirebaseService.users.doc(user.uid).update({
        'authMethod': 'google',
        if ((user.photoURL ?? '').isNotEmpty) 'selfieUrl': user.photoURL,
      });

      _customer = await FirestoreService.getUser(user.uid) ?? customer;
      _state = AuthState.authenticated;
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

  Future<String?> saveLocation({
    required String area,
    required double latitude,
    required double longitude,
  }) async {
    final uid = _customer?.id;
    if (uid == null) return 'You are not signed in.';
    if (area.trim().isEmpty) return 'Tell us your area, estate or landmark.';
    if (latitude == 0 || longitude == 0) {
      return 'Pin your exact location on the map.';
    }

    try {
      await FirebaseService.users.doc(uid).update({
        'county': area.trim(),
        'area': area.trim(),
        'estate': area.trim(),
        'latitude': latitude,
        'longitude': longitude,
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