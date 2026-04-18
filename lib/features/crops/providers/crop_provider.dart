import 'package:flutter/material.dart';
import '../../../models/crop_model.dart';
import '../services/crop_service.dart';

class CropProvider extends ChangeNotifier {
  final CropService _service = CropService();

  List<Crop> _crops = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Crop> get crops => _crops;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get activeCropCount => _crops.where((c) => c.status == 'growing' || c.status == 'planted').length;

  /// Listen to crops for a user
  void loadCrops(String userId) {
    _isLoading = true;
    notifyListeners();

    // Auto-transition planted crops to growing after 1 day
    _service.autoTransitionPlantedCrops(userId).then((_) {
      _service
          .getCrops(userId)
          .listen(
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
    });
  }

  Future<bool> addCrop(String userId, Crop crop) async {
    try {
      await _service.addCrop(userId, crop);
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
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete crop';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
