import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Shared Market queries. Create this with the UID of the active local account.
class MarketFirestore {
  const MarketFirestore(this.firebaseUid);

  final String firebaseUid;

  FirebaseFirestore get _db {
    if (firebaseUid != FirebaseAuth.instance.currentUser?.uid) {
      throw StateError('Sign in to Firebase with your FarmApp account.');
    }
    return FirebaseFirestore.instance;
  }

  CollectionReference<Map<String, dynamic>> get places =>
      _db.collection('market_places');

  DocumentReference<Map<String, dynamic>> profile(String sellerUid) =>
      _db.collection('market_profiles').doc(sellerUid);

  Query<Map<String, dynamic>> publishedProfiles(String districtId) => _db
      .collection('market_profiles')
      .where('districtId', isEqualTo: districtId)
      .where('status', isEqualTo: 'published')
      .orderBy('updatedAt', descending: true);

  Query<Map<String, dynamic>> activeListings(String sellerUid) =>
      profile(sellerUid)
          .collection('listings')
          .where('status', isEqualTo: 'active');

  Query<Map<String, dynamic>> orders({required bool selling}) => _db
      .collection('market_orders')
      .where(selling ? 'sellerUid' : 'buyerUid', isEqualTo: firebaseUid)
      .orderBy('createdAt', descending: true);
}
