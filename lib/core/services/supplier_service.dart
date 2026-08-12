// lib/core/services/supplier_service.dart
//
// Reads the vetted stock-financing supplier directory for the vendor
// stock-loan picker. A vendor selects a supplier + one of its registered
// payment methods; only those two IDs are ever sent to applyPezeshaLoan.
// The real payout numbers are NOT in these docs — they live in a
// server-only suppliers/{id}/payout/{methodId} subcollection the client
// can't read (see firestore.rules). This service exposes only what the
// picker needs: name, brands, and a redacted method list of
// {id, type, label}.

import 'package:cloud_firestore/cloud_firestore.dart';

class SupplierPaymentMethod {
  final String id;
  final String type; // 'till' | 'paybill' | 'mobile' | 'bank'
  final String label;

  const SupplierPaymentMethod({
    required this.id,
    required this.type,
    required this.label,
  });

  factory SupplierPaymentMethod.fromMap(Map<String, dynamic> m) {
    return SupplierPaymentMethod(
      id: (m['id'] ?? '').toString(),
      type: (m['type'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
    );
  }

  // Bank payout isn't wired end-to-end yet (Pezesha has no confirmed
  // bank disbursement type — see pezesha.ts). The picker uses this to
  // disable a bank method rather than let a vendor pick one the server
  // will only reject.
  bool get isPayable => type != 'bank';
}

class Supplier {
  final String id;
  final String name;
  final List<String> brands;
  final List<SupplierPaymentMethod> paymentMethods;

  const Supplier({
    required this.id,
    required this.name,
    required this.brands,
    required this.paymentMethods,
  });

  factory Supplier.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final methods = (d['paymentMethods'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SupplierPaymentMethod.fromMap)
        .toList();
    return Supplier(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      brands: (d['brands'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      paymentMethods: methods,
    );
  }

  // At least one method the server will actually accept.
  bool get hasPayableMethod => paymentMethods.any((m) => m.isPayable);
}

class SupplierService {
  /// Active suppliers serving [country], for the stock-loan picker.
  ///
  /// The status == 'active' filter isn't just UX — firestore.rules only
  /// grants a vendor read on suppliers whose status is 'active', so the
  /// query MUST carry it or the read is denied. (Firestore will ask for
  /// a composite index on status + countries the first time this runs;
  /// follow the link it logs.)
  static Future<List<Supplier>> forCountry(String country) async {
    final snap = await FirebaseFirestore.instance
        .collection('suppliers')
        .where('status', isEqualTo: 'active')
        .where('countries', arrayContains: country)
        .get();
    final suppliers = snap.docs.map(Supplier.fromDoc).toList();
    // Only surface suppliers with a method that can actually be paid.
    return suppliers.where((s) => s.hasPayableMethod).toList();
  }
}
