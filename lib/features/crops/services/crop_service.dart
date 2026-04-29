import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../models/crop_model.dart';

class CropService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Reference to a user's crops collection
  CollectionReference _cropsRef(String userId) {
    return _db.collection('users').doc(userId).collection('crops');
  }

  /// Add a new crop
  Future<DocumentReference> addCrop(String userId, Crop crop) async {
    return await _cropsRef(userId).add(crop.toMap());
  }

  /// Get all crops as a stream
  Stream<List<Crop>> getCrops(String userId) {
    return _cropsRef(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Crop.fromFirestore(doc)).toList());
  }

  /// Get a single crop by ID
  Future<Crop?> getCropById(String userId, String cropId) async {
    final doc = await _cropsRef(userId).doc(cropId).get();
    if (doc.exists) {
      return Crop.fromFirestore(doc);
    }
    return null;
  }

  /// Update an existing crop
  Future<void> updateCrop(String userId, String cropId, Map<String, dynamic> data) async {
    await _cropsRef(userId).doc(cropId).update(data);
  }

  /// Delete a crop
  Future<void> deleteCrop(String userId, String cropId) async {
    await _cropsRef(userId).doc(cropId).delete();
  }

  /// Auto-transition crops from 'planted' to 'growing' after 1 day
  Future<void> autoTransitionPlantedCrops(String userId) async {
    try {
      final snapshot = await _cropsRef(userId)
          .where('status', isEqualTo: 'planted')
          .get();

      final now = DateTime.now();
      final batch = _db.batch();
      bool hasBatchUpdates = false;

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Use plantedDate if available, otherwise fallback to createdAt
        DateTime? referenceDate;
        if (data['plantedDate'] != null) {
          referenceDate = (data['plantedDate'] as Timestamp).toDate();
        } else if (data['createdAt'] != null) {
          referenceDate = (data['createdAt'] as Timestamp).toDate();
        }

        if (referenceDate != null) {
          final difference = now.difference(referenceDate).inDays;
          if (difference >= 1) {
            batch.update(doc.reference, {'status': 'growing'});
            hasBatchUpdates = true;
          }
        }
      }

      if (hasBatchUpdates) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Auto-transition error: $e');
    }
  }

  /// Get total income from sold and consumed crops
  Future<double> getTotalIncome(String userId) async {
    double total = 0.0;

    // Sum soldAmount from crops with status 'sold'
    final soldSnap = await _cropsRef(userId)
        .where('status', isEqualTo: 'sold')
        .get();
    for (var doc in soldSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      total += (data['soldAmount'] ?? 0.0).toDouble();
    }

    // Sum consumedEstimatedAmount from crops with status 'consumed'
    final consumedSnap = await _cropsRef(userId)
        .where('status', isEqualTo: 'consumed')
        .get();
    for (var doc in consumedSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      total += (data['consumedEstimatedAmount'] ?? 0.0).toDouble();
    }

    return total;
  }

  /// Get a stream of crops that have income (sold or consumed)
  Stream<List<Crop>> getIncomeCrops(String userId) {
    return _cropsRef(userId)
        .where('status', whereIn: ['sold', 'consumed'])
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Crop.fromFirestore(doc)).toList());
  }
}
