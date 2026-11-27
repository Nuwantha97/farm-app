import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/farm_reset_service.dart';
import '../../../core/services/hive_service.dart';
import '../../../models/crop_model.dart';
import '../../finance/services/expense_service.dart';

/// Hive-based crop CRUD service.
/// All data is stored locally in an encrypted Hive box.
class CropService {
  static const _uuid = Uuid();

  /// Hive key format: {userId}_{cropId}
  String _key(String userId, String cropId) => '${userId}_$cropId';

  /// Add a new crop to Hive.
  Future<String> addCrop(String userId, Crop crop) async {
    FarmResetService.requireWritable(userId);
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

  /// Get all active (non-archived) crops for a user as a stream.
  Stream<List<Crop>> getCrops(String userId) =>
      _watchCropLists(() => _getCropsList(userId));

  Stream<List<Crop>> _watchCropLists(List<Crop> Function() readCrops) {
    final controller = StreamController<List<Crop>>();
    void listener() {
      if (!controller.isClosed) {
        controller.add(readCrops());
      }
    }

    final crops = HiveService.cropsBox.listenable();
    final history = HiveService.cropHistoryBox.listenable();
    controller.onListen = () {
      crops.addListener(listener);
      history.addListener(listener);
      listener();
    };
    controller.onCancel = () {
      crops.removeListener(listener);
      history.removeListener(listener);
    };

    return controller.stream;
  }

  /// Get active (non-archived, non-deleted) crops as a list.
  List<Crop> _getCropsList(String userId) {
    final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);
    final crops = entries
        .where((entry) => !HiveService.cropHistoryBox.containsKey(entry.key))
        .map((e) => Crop.fromMap(Map<String, dynamic>.from(e.value)))
        .where((c) => c.syncStatus != 'deleted' && !_isArchived(c))
        .toList();

    // Sort by createdAt descending
    crops.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return crops;
  }

  bool _isArchived(Crop crop) => crop.isArchived || crop.archivedAt != null;

  /// Get a single crop by ID.
  Future<Crop?> getCropById(String userId, String cropId) async {
    final data = HiveService.cropsBox.get(_key(userId, cropId));
    if (data != null) {
      return Crop.fromMap(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Update an existing crop.
  Future<bool> updateCrop(
    String userId,
    String cropId,
    Map<String, dynamic> updateData,
  ) async {
    FarmResetService.requireWritable(userId);
    final key = _key(userId, cropId);
    final existing = HiveService.cropsBox.get(key);
    if (existing == null ||
        existing['syncStatus'] == 'deleted' ||
        existing['isArchived'] == true ||
        existing['archivedAt'] != null ||
        HiveService.cropHistoryBox.containsKey(key)) {
      return false;
    }

    final data = Map<String, dynamic>.from(existing);
    data.addAll(updateData);
    data['syncStatus'] = data['firebaseId'] == null ? 'pending' : 'modified';
    data['updatedAt'] = DateTime.now().toIso8601String();

    await HiveService.cropsBox.put(key, Map<String, dynamic>.from(data));
    debugPrint('CropService: Updated crop $cropId');
    return true;
  }

  /// Archive a crop (soft-remove from active list, keep in history).
  /// Only works for 'sold' or 'consumed' crops.
  /// Copies the crop snapshot and its expenses into history boxes.
  Future<bool> archiveCrop(String userId, String cropId) async {
    FarmResetService.requireWritable(userId);
    final key = _key(userId, cropId);
    final existing = HiveService.cropsBox.get(key);
    if (existing == null || existing['syncStatus'] == 'deleted') return false;
    final status = existing['status'];
    if (status != 'sold' && status != 'consumed') return false;
    final history = HiveService.cropHistoryBox.get(key);
    if (history != null && existing['isArchived'] == true) return true;
    final now = DateTime.now().toIso8601String();
    final archivedAt = history?['archivedAt'] ?? existing['archivedAt'] ?? now;

    await ExpenseService.snapshotCropExpenses(userId, cropId, existing, archivedAt);
    FarmResetService.requireWritable(userId);

    final current = HiveService.cropsBox.get(key);
    if (current == null || current['syncStatus'] == 'deleted') return false;
    if (!HiveService.cropHistoryBox.containsKey(key)) {
      await HiveService.cropHistoryBox.put(key, {
        ...current,
        'isArchived': true,
        'archivedAt': archivedAt,
        'updatedAt': now,
        'firebaseId': null,
        'syncStatus': 'pending',
      });
    }

    final latest = HiveService.cropsBox.get(key);
    if (latest == null || latest['syncStatus'] == 'deleted') return false;
    await HiveService.cropsBox.put(key, {
      ...latest,
      'isArchived': true,
      'archivedAt': archivedAt,
      'syncStatus': latest['firebaseId'] == null ? 'pending' : 'modified',
      'updatedAt': DateTime.now().toIso8601String(),
    });

    debugPrint('CropService: Archived crop $cropId');
    return true;
  }

  /// Delete a crop permanently (marks as deleted for sync, removes from history too).
  Future<void> deleteCrop(String userId, String cropId) async {
    FarmResetService.requireWritable(userId);
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

    // Also remove from history boxes (hard delete = gone from everywhere)
    final historyKey = '${userId}_$cropId';
    await HiveService.cropHistoryBox.delete(historyKey);

    // Remove associated expenses from expense history
    final expPrefix = '${userId}_${cropId}_';
    final keysToRemove = HiveService.expenseHistoryBox
        .toMap()
        .keys
        .where((k) => k.toString().startsWith(expPrefix))
        .toList();
    for (final k in keysToRemove) {
      await HiveService.expenseHistoryBox.delete(k);
    }

    debugPrint('CropService: Deleted crop $cropId (including history)');
  }

  /// Auto-transition crops from 'planted' to 'growing' after 1 day.
  Future<void> autoTransitionPlantedCrops(String userId) async {
    if (FarmResetService.isBlocked(userId)) return;
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
          data['syncStatus'] = data['firebaseId'] == null ? 'pending' : 'modified';
          data['updatedAt'] = now.toIso8601String();
          await HiveService.cropsBox.put(
            entry.key,
            Map<String, dynamic>.from(data),
          );
        }
      }
    } catch (e) {
      debugPrint('Auto-transition error: $e');
    }
  }

  /// Get total income from active (non-archived) sold and consumed crops.
  Future<double> getTotalIncome(String userId) async {
    double total = 0.0;
    final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);

    for (final entry in entries) {
      final data = Map<String, dynamic>.from(entry.value);
      final status = data['status'] ?? '';
      if (data['syncStatus'] == 'deleted') continue;
      if (data['isArchived'] == true) continue;

      if (status == 'sold') {
        total += (data['soldAmount'] ?? 0.0).toDouble();
      } else if (status == 'consumed') {
        total += (data['consumedEstimatedAmount'] ?? 0.0).toDouble();
      }
    }
    return total;
  }

  /// Get a stream of active (non-archived) crops that have income.
  Stream<List<Crop>> getIncomeCrops(String userId) {
    final controller = StreamController<List<Crop>>();

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
        .where(
          (c) =>
              (c.status == 'sold' || c.status == 'consumed') &&
              c.syncStatus != 'deleted' &&
              !c.isArchived,
        )
        .toList();
  }

  // ── History methods ──────────────────────────────────────────

  /// Watch archived crops, including ones whose history snapshot has yet to sync.
  Stream<List<Crop>> getHistoryCrops(String userId) =>
      _watchCropLists(() => _getHistoryCropsList(userId));

  List<Crop> _getHistoryCropsList(String userId) {
    final byKey = <String, Crop>{};
    for (final entry in HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    )) {
      final crop = Crop.fromMap(Map<String, dynamic>.from(entry.value));
      if (crop.syncStatus != 'deleted' && _isArchived(crop)) {
        byKey[entry.key] = crop;
      }
    }
    for (final entry in HiveService.getItemsByUser(
      HiveService.cropHistoryBox,
      userId,
    )) {
      byKey[entry.key] = Crop.fromMap(Map<String, dynamic>.from(entry.value));
    }
    final crops = byKey.values.toList();

    // Sort by archivedAt descending
    crops.sort(
      (a, b) =>
          (b.archivedAt ?? b.createdAt).compareTo(a.archivedAt ?? a.createdAt),
    );
    return crops;
  }

  /// Get all-time total income (active + archived crops).
  Future<double> getAllTimeTotalIncome(String userId) async {
    double total = 0.0;

    // Active crops
    final activeEntries = HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    );
    for (final entry in activeEntries) {
      final data = Map<String, dynamic>.from(entry.value);
      final status = data['status'] ?? '';
      if (data['syncStatus'] == 'deleted') continue;

      if (status == 'sold') {
        total += (data['soldAmount'] ?? 0.0).toDouble();
      } else if (status == 'consumed') {
        total += (data['consumedEstimatedAmount'] ?? 0.0).toDouble();
      }
    }

    // Archived crops (from history box)
    final historyEntries = HiveService.getItemsByUser(
      HiveService.cropHistoryBox,
      userId,
    );
    for (final entry in historyEntries) {
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
}
