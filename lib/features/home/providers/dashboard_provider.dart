import 'package:flutter/material.dart';
import '../../../features/crops/services/crop_service.dart';
import '../../../features/finance/services/expense_service.dart';

class DashboardProvider extends ChangeNotifier {
  final CropService _cropService = CropService();
  final ExpenseService _expenseService = ExpenseService();

  int _totalCrops = 0;
  int _activeCrops = 0;
  double _totalExpenses = 0.0;
  bool _isLoading = false;

  int get totalCrops => _totalCrops;
  int get activeCrops => _activeCrops;
  double get totalExpenses => _totalExpenses;
  bool get isLoading => _isLoading;

  /// Load dashboard data
  void loadDashboard(String userId) {
    _isLoading = true;
    notifyListeners();

    // Listen to crops for counts
    _cropService.getCrops(userId).listen(
      (crops) {
        _totalCrops = crops.length;
        _activeCrops = crops.where((c) => c.status == 'active').length;
        _isLoading = false;
        notifyListeners();
      },
      onError: (e) {
        _isLoading = false;
        notifyListeners();
      },
    );

    // Fetch total expenses
    _expenseService.getTotalExpenses(userId).then((total) {
      _totalExpenses = total;
      notifyListeners();
    }).catchError((_) {});
  }

  /// Refresh expenses total
  Future<void> refreshExpenses(String userId) async {
    _totalExpenses = await _expenseService.getTotalExpenses(userId);
    notifyListeners();
  }
}
