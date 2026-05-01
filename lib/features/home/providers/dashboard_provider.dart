import 'dart:async';

import 'package:flutter/material.dart';
import '../../../features/crops/services/crop_service.dart';
import '../../../features/finance/services/expense_service.dart';

class DashboardProvider extends ChangeNotifier {
  final CropService _cropService = CropService();
  final ExpenseService _expenseService = ExpenseService();

  int _totalCrops = 0;
  int _activeCrops = 0;
  double _totalExpenses = 0.0;
  double _totalIncome = 0.0;
  bool _isLoading = false;

  StreamSubscription? _cropsSub;

  int get totalCrops => _totalCrops;
  int get activeCrops => _activeCrops;
  double get totalExpenses => _totalExpenses;
  double get totalIncome => _totalIncome;
  double get totalProfit => _totalIncome - _totalExpenses;
  bool get isLoading => _isLoading;

  /// Load dashboard data from Hive.
  void loadDashboard(String userId) {
    _isLoading = true;
    notifyListeners();

    // Auto-transition planted crops to growing after 1 day, then listen
    _cropService.autoTransitionPlantedCrops(userId).then((_) {
      _cropsSub?.cancel();
      _cropsSub = _cropService.getCrops(userId).listen(
        (crops) {
          _totalCrops = crops.length;
          _activeCrops = crops
              .where((c) => c.status == 'growing' || c.status == 'planted')
              .length;
          _isLoading = false;
          notifyListeners();
        },
        onError: (e) {
          _isLoading = false;
          notifyListeners();
        },
      );
    });

    // Fetch total expenses
    _expenseService
        .getTotalExpenses(userId)
        .then((total) {
          _totalExpenses = total;
          notifyListeners();
        })
        .catchError((_) {});

    // Fetch total income
    _expenseService
        .getTotalIncome(userId)
        .then((total) {
          _totalIncome = total;
          notifyListeners();
        })
        .catchError((_) {});
  }

  /// Refresh expenses total.
  Future<void> refreshExpenses(String userId) async {
    _totalExpenses = await _expenseService.getTotalExpenses(userId);
    _totalIncome = await _expenseService.getTotalIncome(userId);
    notifyListeners();
  }

  @override
  void dispose() {
    _cropsSub?.cancel();
    super.dispose();
  }
}
