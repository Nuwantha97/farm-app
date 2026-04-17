import 'package:cloud_firestore/cloud_firestore.dart';
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
}
