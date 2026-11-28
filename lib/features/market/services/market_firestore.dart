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

  /// Close discovery before deleting the Firebase account. A closed profile
  /// blocks republishing from another device and contains no public details.
  Future<void> closeMarketForAccountDeletion() async {
    final document = profile(firebaseUid);
    await _db.runTransaction<void>((transaction) async {
      final current = await transaction.get(document);
      if (current.data()?['status'] == 'closed') return;
      transaction.set(document, {
        'status': 'closed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    await _resolveOpenOrders(selling: true);
    await _resolveOpenOrders(selling: false);
  }

  Future<void> _resolveOpenOrders({required bool selling}) async {
    const openStatuses = ['requested', 'accepted'];
    const server = GetOptions(source: Source.server);
    final openOrders = _db
        .collection('market_orders')
        .where(selling ? 'sellerUid' : 'buyerUid', isEqualTo: firebaseUid)
        .where('status', whereIn: openStatuses)
        .limit(50);
    while (true) {
      final orders = (await openOrders.get(server)).docs;
      if (orders.isEmpty) return;
      for (final order in orders) {
        final status = order.data()['status'] as String;
        final destination = selling && status == 'requested'
            ? 'declined'
            : 'cancelled';
        try {
          await changeOrderStatus(order.id, status, destination);
        } on StateError {
          final latest = (await order.reference.get(server)).data()?['status'];
          if (openStatuses.contains(latest)) rethrow;
        }
      }
    }
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

  Future<void> saveListing(
    String id,
    Map<String, dynamic> fields, {
    Object? expectedStock,
  }) {
    final listing = ownListings.doc(id);
    return _db.runTransaction<void>((transaction) async {
      final current = (await transaction.get(listing)).data();
      if (expectedStock != null &&
          current?['availableQuantity'] != expectedStock) {
        throw StateError(
          'Stock changed. Reopen the offer and review the current quantity.',
        );
      }
      if ((current?['reservedQuantity'] as int? ?? 0) > 0 &&
          (current?['unit'] != fields['unit'] ||
              current?['produceName'] != fields['produceName'])) {
        throw StateError(
          'Finish or cancel the reserved orders before changing the produce or unit.',
        );
      }
      transaction.set(listing, {
        ...?current,
        ...fields,
        'status': current?['status'] ?? 'active',
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

  Future<void> changeOrderStatus(String id, String from, String to) {
    final db = _db;
    final order = db.collection('market_orders').doc(id);
    return db.runTransaction<void>((transaction) async {
      final data = (await transaction.get(order)).data();
      if (data == null) throw StateError('This request is unavailable.');
      if (data['status'] == to) return;
      if (data['status'] != from) {
        throw StateError(
          'This order already changed. Review its latest status.',
        );
      }
      if (to == 'accepted' || from == 'accepted') {
        final offer = profile(data['sellerUid'] as String)
            .collection('listings')
            .doc(data['listingId'] as String);
        final quantity = data['quantity'] as int;
        if (to == 'accepted') {
          final stock = (await transaction.get(offer)).data();
          if (stock == null ||
              stock['status'] != 'active' ||
              stock['unit'] != data['unit'] ||
              stock['produceName'] != data['produceName']) {
            throw StateError('The original offer is no longer available.');
          }
          final available = stock['availableQuantity'] as int;
          if (available < quantity) {
            final unit = data['unit'] as String;
            final shown = listingInput(available, unit == 'kg' ? 3 : 0);
            throw StateError(
              'Only $shown $unit remain. This request was not accepted.',
            );
          }
        }
        transaction.update(offer, {
          if (to != 'completed')
            'availableQuantity': FieldValue.increment(
              to == 'accepted' ? -quantity : quantity,
            ),
          'reservedQuantity': FieldValue.increment(
            to == 'accepted' ? quantity : -quantity,
          ),
        });
        transaction.set(offer.collection('operations').doc('stock'), {
          'orderId': id,
        });
      }
      transaction.update(order, {
        'status': to,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> savePickupInstructions(String id, String instructions) {
    final db = _db;
    final order = db.collection('market_orders').doc(id);
    return db.runTransaction<void>((transaction) async {
      final data = (await transaction.get(order)).data();
      if (data?['status'] != 'accepted') {
        throw StateError(
          'Pickup instructions can only be changed for an accepted order.',
        );
      }
      transaction.update(order, {
        'pickupInstructions': instructions,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Returns revised terms for review or the original order on a recovered retry.
  Future<
    ({Map<String, dynamic>? revisedOffer, Map<String, dynamic>? existingOrder})
  >
  requestOrder({
    required String requestId,
    required String sellerUid,
    required String listingId,
    required Map<String, dynamic> reviewed,
    required int? quantity,
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
        return (revisedOffer: null, existingOrder: existing);
      }
      if (quantity == null) {
        throw StateError(
          'No previous request was saved. Review the offer and request to buy.',
        );
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
      if (terms.any((field) => latest[field] != reviewed[field])) {
        return (revisedOffer: latest, existingOrder: null);
      }
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
      return (revisedOffer: null, existingOrder: null);
    });
  }
}
