import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';

enum AuthState { unauthenticated, loading, authenticated }

class AuthProvider extends ChangeNotifier {
  AuthState _state = AuthState.unauthenticated;
  CustomerModel? _customer;
  String? _error;

  AuthState get state => _state;
  CustomerModel? get customer => _customer;
  String? get error => _error;
  bool get isAuthenticated => _state == AuthState.authenticated;

  Future<void> login(String phone, String password) async {
    _state = AuthState.loading;
    _error = null;
    notifyListeners();

    // TODO: replace with real Firebase auth
    await Future.delayed(const Duration(seconds: 2));

    // Mock successful login
    _customer = CustomerModel(
      id: 'c001',
      name: 'Jane Wanjiku',
      phone: phone,
      nationalId: '12345678',
      county: 'Nairobi',
      area: 'Kasarani',
      estate: 'Mirema Drive',
      latitude: -1.2234,
      longitude: 36.8901,
      bankApprovedLimit: 3200,
      bankCreditUsed: 0,
      bankStatus: BankApprovalStatus.approved,
      partnerBankName: 'Stima SACCO',
      guarantors: [],
    );
    _state = AuthState.authenticated;
    notifyListeners();
  }

  Future<void> register({
    required String name,
    required String phone,
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

    // TODO: replace with real Firebase + backend call
    await Future.delayed(const Duration(seconds: 2));

    // Mock: create customer and pass KYC to bank
    _customer = CustomerModel(
      id: 'c${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      phone: phone,
      nationalId: nationalId,
      county: county,
      area: area,
      estate: estate,
      latitude: latitude,
      longitude: longitude,
      bankApprovedLimit: null, // pending bank approval
      bankCreditUsed: 0,
      bankStatus: BankApprovalStatus.pending,
      partnerBankName: '',
      guarantors: guarantors,
    );
    _state = AuthState.authenticated;
    notifyListeners();
  }

  void logout() {
    _state = AuthState.unauthenticated;
    _customer = null;
    notifyListeners();
  }
}
