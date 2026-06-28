import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';

enum AuthState { unauthenticated, loading, authenticated }

class AuthProvider extends ChangeNotifier {
  AuthState _state = AuthState.unauthenticated;
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
      } else {
        // Load customer from Firestore
        final customer = await FirestoreService.getUser(user.uid);
        if (customer != null) {
          _customer = customer;
          _state = AuthState.authenticated;
          notifyListeners();
        }
      }
    });
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

      final customer =
          await FirestoreService.getUser(credential.user!.uid);
      _customer = customer;
      _state = AuthState.authenticated;
      notifyListeners();
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
  }) async {
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    try {
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
        phone: phone,
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

      // Upload selfie to Firebase Storage
      String? selfieUrl;
      if (selfieFile != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('selfies')
            .child(uid);
        await ref.putFile(selfieFile);
        selfieUrl = await ref.getDownloadURL();
      }

      // Save to Firestore
      await FirestoreService.createUser(customer);
      if (selfieUrl != null) {
        await FirebaseService.users.doc(uid).update({'selfieUrl': selfieUrl});
      }

      // Submit KYC to bank application queue
      await FirestoreService.submitBankApplication(
        customerId: uid,
        name: name,
        phone: phone,
        nationalId: nationalId,
        county: county,
        area: area,
        guarantors: guarantors
            .map((g) => {'name': g.name, 'phone': g.phone})
            .toList(),
      );

      _customer = customer;
      _state = AuthState.authenticated;
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      _error = _authError(e.code);
      _state = AuthState.unauthenticated;
      notifyListeners();
    }
  }

  Future<void> submitCreditApplication({
    required List<GuarantorModel> guarantors,
  }) async {
    if (_customer == null) return;

    // Update customer with guarantors
    _customer = CustomerModel(
      id: _customer!.id,
      name: _customer!.name,
      phone: _customer!.phone,
      nationalId: _customer!.nationalId,
      county: _customer!.county,
      area: _customer!.area,
      estate: _customer!.estate,
      latitude: _customer!.latitude,
      longitude: _customer!.longitude,
      bankApprovedLimit: _customer!.bankApprovedLimit,
      bankCreditUsed: _customer!.bankCreditUsed,
      bankStatus: BankApprovalStatus.pending,
      partnerBankName: _customer!.partnerBankName,
      guarantors: guarantors,
    );

    // Save guarantors to Firestore
    await FirestoreService.updateUserBankStatus(
      uid: _customer!.id,
      status: BankApprovalStatus.pending,
    );

    // Submit KYC to bank application queue
    await FirestoreService.submitBankApplication(
      customerId: _customer!.id,
      name: _customer!.name,
      phone: _customer!.phone,
      nationalId: _customer!.nationalId,
      county: _customer!.county,
      area: _customer!.area,
      guarantors: guarantors
          .map((g) => {'name': g.name, 'phone': g.phone})
          .toList(),
    );

    notifyListeners();
  }

  Future<void> resetPassword(String email) async {
    await FirebaseService.auth.sendPasswordResetEmail(email: email);
  }

  Future<void> requestBankApproval() async {
    if (_customer == null) return;

    // Poll Firestore for bank response
    // In real system: bank API calls our backend webhook
    // Backend updates bank_applications collection
    // We listen for changes here

    // TODO: real bank webhook integration
    // For pilot: manual approval via admin dashboard
    await Future.delayed(const Duration(seconds: 2));

    // Check if bank has responded
    final updated = await FirestoreService.getUser(_customer!.id);
    if (updated != null) {
      _customer = updated;
      notifyListeners();
    }
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
        return 'No account found with this phone number';
      case 'wrong-password':
        return 'Incorrect password';
      case 'email-already-in-use':
        return 'An account already exists with this phone number';
      case 'weak-password':
        return 'Password must be at least 6 characters';
      case 'network-request-failed':
        return 'No internet connection';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
