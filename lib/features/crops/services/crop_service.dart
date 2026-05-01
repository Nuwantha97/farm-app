import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/hive_service.dart';
import '../../../models/crop_model.dart';

/// Hive-based crop CRUD service.
/// All data is stored locally in an encrypted Hive box.
class CropService {
  static const _uuid = Uuid();

  /// Hive key format: {userId}_{cropId}
  String _key(String userId, String cropId) => '${userId}_$cropId';

  /// Add a new crop to Hive.
  Future<String> addCrop(String userId, Crop crop) async {
    final cropId = _uuid.v4();
    final newCrop = crop.copyWith(
      id: cropId,
      localId: cropId,
      syncStatus: 'pending',
      updatedAt: DateTime.now(),
    );
    await HiveService.cropsBox.put(
      _key(userId, cropId),
      Map<String, dynamic>.from(newCrop.toHiveMap()),
    );
    debugPrint('CropService: Added crop $cropId');
    return cropId;
  }

  /// Get all crops for a user as a stream (reactive via ValueListenable).
  Stream<List<Crop>> getCrops(String userId) {
    // Create a stream from Hive's ValueListenable
    final controller = StreamController<List<Crop>>.broadcast();

    // Emit initial value
    controller.add(_getCropsList(userId));

    // Listen for changes
    void listener() {
      if (!controller.isClosed) {
        controller.add(_getCropsList(userId));
      }
    }

    HiveService.cropsBox.listenable().addListener(listener);

    controller.onCancel = () {
      HiveService.cropsBox.listenable().removeListener(listener);
    };

    return controller.stream;
  }

  /// Get all crops as a list (non-reactive, single read).
  List<Crop> _getCropsList(String userId) {
    final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);
    final crops = entries
        .map((e) => Crop.fromMap(Map<String, dynamic>.from(e.value)))
        .where((c) => c.syncStatus != 'deleted')
        .toList();

    // Sort by createdAt descending
    crops.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return crops;
  }

  /// Get a single crop by ID.
  Future<Crop?> getCropById(String userId, String cropId) async {
    final data = HiveService.cropsBox.get(_key(userId, cropId));
    if (data != null) {
      return Crop.fromMap(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Update an existing crop.
  Future<void> updateCrop(
      String userId, String cropId, Map<String, dynamic> updateData) async {
    final key = _key(userId, cropId);
    final existing = HiveService.cropsBox.get(key);
    if (existing == null) return;

    final data = Map<String, dynamic>.from(existing);
    data.addAll(updateData);
    data['syncStatus'] = 'modified';
    data['updatedAt'] = DateTime.now().toIso8601String();

    await HiveService.cropsBox.put(key, Map<String, dynamic>.from(data));
    debugPrint('CropService: Updated crop $cropId');
  }

  /// Delete a crop (marks as deleted for sync, then removes after sync).
  Future<void> deleteCrop(String userId, String cropId) async {
    final key = _key(userId, cropId);
    final existing = HiveService.cropsBox.get(key);

    if (existing != null) {
      final data = Map<String, dynamic>.from(existing);
      if (data['firebaseId'] != null) {
        // Has been synced — mark as deleted for sync service to handle
        data['syncStatus'] = 'deleted';
        data['updatedAt'] = DateTime.now().toIso8601String();
        await HiveService.cropsBox.put(key, Map<String, dynamic>.from(data));
      } else {
        // Never synced — just delete locally
        await HiveService.cropsBox.delete(key);
      }
    }
    debugPrint('CropService: Deleted crop $cropId');
  }

  /// Auto-transition crops from 'planted' to 'growing' after 1 day.
  Future<void> autoTransitionPlantedCrops(String userId) async {
    try {
      final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);
      final now = DateTime.now();

      for (final entry in entries) {
        final data = Map<String, dynamic>.from(entry.value);
        if (data['status'] != 'planted') continue;

        DateTime? referenceDate;
        if (data['plantedDate'] != null) {
          referenceDate = DateTime.parse(data['plantedDate']);
        } else if (data['createdAt'] != null) {
          referenceDate = DateTime.parse(data['createdAt']);
        }

        if (referenceDate != null &&
            now.difference(referenceDate).inDays >= 1) {
          data['status'] = 'growing';
          data['syncStatus'] = 'modified';
          data['updatedAt'] = now.toIso8601String();
          await HiveService.cropsBox
              .put(entry.key, Map<String, dynamic>.from(data));
        }
      }
    } catch (e) {
      debugPrint('Auto-transition error: $e');
    }
  }

  /// Get total income from sold and consumed crops.
  Future<double> getTotalIncome(String userId) async {
    double total = 0.0;
    final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);

    for (final entry in entries) {
      final data = Map<String, dynamic>.from(entry.value);
      final status = data['status'] ?? '';

      if (status == 'sold') {
        total += (data['soldAmount'] ?? 0.0).toDouble();
      } else if (status == 'consumed') {
        total += (data['consumedEstimatedAmount'] ?? 0.0).toDouble();
      }
    }
    return total;
  }

  /// Get a stream of crops that have income (sold or consumed).
  Stream<List<Crop>> getIncomeCrops(String userId) {
    final controller = StreamController<List<Crop>>.broadcast();

    controller.add(_getIncomeCropsList(userId));

    void listener() {
      if (!controller.isClosed) {
        controller.add(_getIncomeCropsList(userId));
      }
    }

    HiveService.cropsBox.listenable().addListener(listener);
    controller.onCancel = () {
      HiveService.cropsBox.listenable().removeListener(listener);
    };

    return controller.stream;
  }

  List<Crop> _getIncomeCropsList(String userId) {
    final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);
    return entries
        .map((e) => Crop.fromMap(Map<String, dynamic>.from(e.value)))
        .where((c) =>
            (c.status == 'sold' || c.status == 'consumed') &&
            c.syncStatus != 'deleted')
        .toList();
  }
}
