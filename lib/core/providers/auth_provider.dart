import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobigas/core/services/storage_metadata.dart';
import 'dart:io';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/device_fingerprint_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';

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

  AuthState get state => _state;
  CustomerModel? get customer => _customer;
  String? get error => _error;
  bool get isAuthenticated => _state == AuthState.authenticated;

  AuthProvider() {
    // Listen to Firebase auth state changes
    FirebaseService.auth.authStateChanges().listen((user) async {
      if (user == null) {
        _state = AuthState.unauthenticated;
        _customer = null;
        notifyListeners();
        return;
      }
      await _loadCustomerWithRetry(user.uid);
    });
  }

  /// Loads the customer's Firestore profile after Firebase Auth
  /// confirms a signed-in user, retrying with backoff before giving
  /// up. A fresh install has no local Firestore cache yet, so the
  /// very first read after reinstall is genuinely slower and more
  /// failure-prone than normal — previously, a single transient
  /// failure here was treated identically to "this account was
  /// deleted, sign the user out", which is why a fresh install could
  /// show blank data until a manual logout/login forced a clean,
  /// fully-awaited re-fetch through login() instead.
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
      // No document yet — could be a brand-new signup whose write
      // hasn't landed, not necessarily a deleted account. Retry a
      // couple of times before concluding it's really missing.
      if (attempt < 2) {
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        return _loadCustomerWithRetry(uid, attempt: attempt + 1);
      }
      _state = AuthState.unauthenticated;
      _customer = null;
      notifyListeners();
    } catch (e) {
      // Network/transient error — retry with backoff instead of
      // immediately treating a signed-in user as logged out.
      if (attempt < maxRetries) {
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        return _loadCustomerWithRetry(uid, attempt: attempt + 1);
      }
      _error = 'Could not load your profile. Check your connection.';
      // Deliberately NOT forcing unauthenticated here — a real
      // connectivity issue shouldn't look identical to "logged out"
      // and boot the user to the login screen over a network blip.
      notifyListeners();
    }
  }

  Future<void> login(String phone, String password) async {
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    try {
      final credential =
          await FirebaseService.auth.signInWithEmailAndPassword(
        email: phone.trim().toLowerCase(),
        password: password,
      );

      await _loadCustomerWithRetry(credential.user!.uid);
    } on FirebaseAuthException catch (e) {
      _error = _authError(e.code);
      _state = AuthState.unauthenticated;
      notifyListeners();
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    File? selfieFile,
    required String nationalId,
    required String county,
    required String area,
    required String estate,
    required double latitude,
    required double longitude,
    required String password,
    required List<GuarantorModel> guarantors,
    String? referralCode,
  }) async {
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    try {
      // Capture device fingerprint for fraud prevention
      final deviceFingerprint = await DeviceFingerprintService.getFingerprint();

      // Check for duplicate phone (and National ID when one was
      // provided — it's optional in v1), and flag shared-device usage.
      final duplicates = await FirestoreService.checkDuplicates(
        phone: phone.trim(),
        nationalId: nationalId.trim(),
        deviceFingerprint: deviceFingerprint,
      );

      if (duplicates['phoneTaken'] == true) {
        _error = 'An account already exists with this phone number. Please sign in instead.';
        _state = AuthState.unauthenticated;
        notifyListeners();
        return;
      }

      // Only enforce the ID-duplicate guard when the customer actually
      // entered an ID — a blank ID can never be "taken".
      if (nationalId.trim().isNotEmpty && duplicates['idTaken'] == true) {
        _error = 'An account already exists with this National ID. Please sign in instead.';
        _state = AuthState.unauthenticated;
        notifyListeners();
        return;
      }

      // Use email for Firebase Auth
      // Phone is stored in Firestore profile
      final credential =
          await FirebaseService.auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      final uid = credential.user!.uid;

      final customer = CustomerModel(
        id: uid,
        name: name,
        email: email.trim().toLowerCase(),
        phone: phone,
        deviceFingerprint: deviceFingerprint,
        deviceFlagged: duplicates['deviceFlagged'] ?? false,
        nationalId: nationalId,
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

      // Create the customer profile. Kick the optional selfie upload
      // off in parallel (Storage write is independent of the Firestore
      // profile write), then patch in the URL once it lands.
      final selfieUploadFuture = selfieFile == null
          ? Future<String?>.value(null)
          : (() async {
              final ref =
                  FirebaseStorage.instance.ref().child('selfies').child(uid);
              await ref.putFile(selfieFile, imageMetadata(selfieFile));
              return ref.getDownloadURL();
            })();

      await FirestoreService.createUser(customer);

      final selfieUrl = await selfieUploadFuture;
      if (selfieUrl != null) {
        await FirebaseService.users.doc(uid).update({'selfieUrl': selfieUrl});
      }

      // Optional — a customer isn't blocked from signing up over an
      // invalid/mistyped code; recordReferralSignup silently no-ops
      // if the code doesn't resolve to anyone.
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

      _customer = customer;
      _state = AuthState.authenticated;
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      _error = _authError(e.code);
      _state = AuthState.unauthenticated;
      notifyListeners();
    }
  }

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

  void logout() {
    FirebaseService.auth.signOut();
    _state = AuthState.unauthenticated;
    _customer = null;
    notifyListeners();
  }

  String _authError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'email-already-in-use':
        return 'An account already exists with this email';
      case 'weak-password':
        return 'Password must be at least 6 characters';
      case 'network-request-failed':
        return 'No internet connection';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}