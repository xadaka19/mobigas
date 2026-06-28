import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get db => FirebaseFirestore.instance;

  static Future<void> initialize() async {
    await Firebase.initializeApp();
  }

  // Collections
  static CollectionReference get users => db.collection('users');
  static CollectionReference get vendors => db.collection('vendors');
  static CollectionReference get orders => db.collection('orders');
  static CollectionReference get repayments => db.collection('repayments');
  static CollectionReference get disbursements =>
      db.collection('disbursements');
  static CollectionReference get bankApplications =>
      db.collection('bank_applications');
}
