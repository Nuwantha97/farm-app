import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/listing_values.dart';

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

  Future<void> publishProfile({
    required String displayName,
    required String farmName,
    required String introduction,
    required String placeId,
    required String districtId,
  }) {
    final document = profile(firebaseUid);
    return _db.runTransaction<void>((transaction) async {
      transaction.set(document, {
        'displayName': displayName,
        'farmName': farmName,
        'introduction': introduction,
        'placeId': placeId,
        'districtId': districtId,
        'status': 'published',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> hideProfile() {
    final document = profile(firebaseUid);
    return _db.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(document);
      if (snapshot.data()?['status'] == 'published') {
        transaction.update(document, {
          'status': 'hidden',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Query<Map<String, dynamic>> publishedProfiles(String districtId) => _db
      .collection('market_profiles')
      .where('districtId', isEqualTo: districtId)
      .where('status', isEqualTo: 'published')
      .orderBy('updatedAt', descending: true);

  Query<Map<String, dynamic>> activeListings(String sellerUid) =>
      profile(sellerUid)
          .collection('listings')
          .where('status', isEqualTo: 'active');

  CollectionReference<Map<String, dynamic>> get ownListings =>
      profile(firebaseUid).collection('listings');

  Future<void> saveListing(String id, Map<String, dynamic> fields) {
    final listing = ownListings.doc(id);
    return _db.runTransaction<void>((transaction) async {
      final current = await transaction.get(listing);
      transaction.set(listing, {
        ...fields,
        'status': current.data()?['status'] ?? 'active',
      });
    });
  }

  Future<void> setListingPaused(String id, bool paused) {
    final listing = ownListings.doc(id);
    return _db.runTransaction<void>((transaction) async {
      transaction.update(listing, {'status': paused ? 'paused' : 'active'});
    });
  }

  Query<Map<String, dynamic>> orders({required bool selling}) => _db
      .collection('market_orders')
      .where(selling ? 'sellerUid' : 'buyerUid', isEqualTo: firebaseUid)
      .orderBy('createdAt', descending: true);

  /// Returns updated offer terms that the buyer must review, or null on success.
  Future<Map<String, dynamic>?> requestOrder({
    required String requestId,
    required String sellerUid,
    required String listingId,
    required Map<String, dynamic> reviewed,
    required int quantity,
  }) {
    if (sellerUid == firebaseUid) {
      throw StateError('You cannot buy your own offer.');
    }
    final db = _db;
    final order = db.collection('market_orders').doc('$firebaseUid~$requestId');
    final shop = profile(sellerUid);
    final offer = shop.collection('listings').doc(listingId);
    return db.runTransaction((transaction) async {
      final existing = (await transaction.get(order)).data();
      if (existing != null) {
        if (existing['sellerUid'] != sellerUid ||
            existing['listingId'] != listingId) {
          throw StateError('This request belongs to another offer.');
        }
        return null;
      }
      final shopData = (await transaction.get(shop)).data();
      final current = (await transaction.get(offer)).data();
      if (shopData?['status'] != 'published' ||
          current?['status'] != 'active') {
        throw StateError('This offer is no longer available.');
      }
      final latest = current!;
      const terms = [
        'produceName',
        'unit',
        'pricePerUnitCents',
        'minimumQuantity',
        'availableQuantity',
        'pickupWindow',
      ];
      if (terms.any((field) => latest[field] != reviewed[field])) return latest;
      final unit = latest['unit'] as String;
      final price = latest['pricePerUnitCents'] as int;
      final total = marketOrderTotal(price, quantity, unit);
      if (quantity < (latest['minimumQuantity'] as int) ||
          quantity > (latest['availableQuantity'] as int) ||
          total == null) {
        throw StateError('Choose a quantity within the limits shown.');
      }
      transaction.set(order, {
        'buyerUid': firebaseUid,
        'sellerUid': sellerUid,
        'listingId': listingId,
        'produceName': latest['produceName'],
        'unit': unit,
        'pricePerUnitCents': price,
        'quantity': quantity,
        'totalCents': total,
        'status': 'requested',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    });
  }
}
