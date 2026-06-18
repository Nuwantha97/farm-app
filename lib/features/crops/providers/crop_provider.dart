import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/services/sync_service.dart';
import '../../../models/crop_model.dart';
import '../services/crop_service.dart';

class CropProvider extends ChangeNotifier {
  final CropService _service = CropService();
  final SyncService _syncService = SyncService();

  List<Crop> _crops = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<List<Crop>>? _cropsSubscription;

  List<Crop> get crops => _crops;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Fire-and-forget sync after a local CRUD operation.
  void _triggerSync(String userId) {
    _syncService.immediateSync(userId).catchError((_) {});
  }

  int get activeCropCount =>
      _crops.where((c) => c.status == 'growing' || c.status == 'planted').length;

  /// Listen to crops for a user (reactive from Hive).
  void loadCrops(String userId) {
    _isLoading = true;
    notifyListeners();

    // Auto-transition planted crops to growing after 1 day
    _service.autoTransitionPlantedCrops(userId).then((_) {
      _cropsSubscription?.cancel();
      _cropsSubscription = _service.getCrops(userId).listen(
        (cropList) {
          _crops = cropList;
          _isLoading = false;
          notifyListeners();
        },
        onError: (e) {
          _errorMessage = 'Failed to load crops';
          _isLoading = false;
          notifyListeners();
        },
      );

      // Fetch from Firebase in background and merge into Hive.
      // The Hive listener above will automatically pick up changes.
      SyncService().backgroundPull(userId);
    });
  }

  Future<bool> addCrop(String userId, Crop crop) async {
    try {
      await _service.addCrop(userId, crop);
      _triggerSync(userId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add crop';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateCrop(
    String userId,
    String cropId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _service.updateCrop(userId, cropId, data);
      _triggerSync(userId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update crop';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCrop(String userId, String cropId) async {
    try {
      await _service.deleteCrop(userId, cropId);
      _triggerSync(userId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete crop';
      notifyListeners();
      return false;
    }
  }

  /// Archive a crop (remove from active list, keep in history).
  Future<bool> archiveCrop(String userId, String cropId) async {
    try {
      await _service.archiveCrop(userId, cropId);
      _triggerSync(userId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to archive crop';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Pull-to-refresh: sync with cloud and re-run auto-transitions.
  Future<void> refresh(String userId) async {
    await _service.autoTransitionPlantedCrops(userId);
    await _syncService.immediateSync(userId);
  }

  @override
  void dispose() {
    _cropsSubscription?.cancel();
    super.dispose();
  }
}
