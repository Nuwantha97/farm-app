import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/sync_service.dart';
import '../../../features/crops/services/crop_service.dart';
import '../../../features/finance/services/expense_service.dart';
import '../../../models/crop_model.dart';
import '../../../models/expense_model.dart';

class HistoryProvider extends ChangeNotifier {
  final CropService _cropService = CropService();
  final ExpenseService _expenseService = ExpenseService();

  List<Crop> _archivedCrops = [];
  List<Expense> _archivedCommonExpenses = [];
  List<Expense> _archivedCropExpenses = [];
  double _allTimeTotalIncome = 0.0;
  double _allTimeTotalExpenses = 0.0;
  bool _isLoading = false;

  StreamSubscription<List<Crop>>? _historySub;
  StreamSubscription<({List<Expense> common, List<Expense> crops})>?
  _expensesSub;
  StreamSubscription<({double expenses, double income})>? _totalsSub;

  List<Crop> get archivedCrops => _archivedCrops;
  List<Expense> get archivedCommonExpenses => _archivedCommonExpenses;
  List<Expense> get archivedCropExpenses => _archivedCropExpenses;
  double get allTimeTotalIncome => _allTimeTotalIncome;
  double get allTimeTotalExpenses => _allTimeTotalExpenses;
  double get allTimeProfit => _allTimeTotalIncome - _allTimeTotalExpenses;
  bool get isLoading => _isLoading;

  /// Load all-time history data.
  void loadHistory(String userId) {
    _isLoading = true;
    notifyListeners();

    // Listen to archived crops from history box
    _historySub?.cancel();
    _historySub = _cropService
        .getHistoryCrops(userId)
        .listen(
          (crops) {
            _archivedCrops = crops;
            _isLoading = false;
            notifyListeners();
          },
          onError: (e) {
            _isLoading = false;
            notifyListeners();
          },
        );

    _expensesSub?.cancel();
    _expensesSub = _expenseService.watchArchivedExpenses(userId).listen((
      expenses,
    ) {
      _archivedCommonExpenses = expenses.common;
      _archivedCropExpenses = expenses.crops;
      notifyListeners();
    });

    _totalsSub?.cancel();
    _totalsSub = _expenseService.watchTotals(userId, allTime: true).listen((
      totals,
    ) {
      _allTimeTotalExpenses = totals.expenses;
      _allTimeTotalIncome = totals.income;
      notifyListeners();
    }, onError: (Object error) => debugPrint('History totals: $error'));

    // Background pull
    SyncService().backgroundPull(userId);
  }

  Future<void> _fetchAllTimeTotals(String userId) async {
    try {
      _allTimeTotalIncome = await _expenseService.getAllTimeTotalIncome(userId);
      _allTimeTotalExpenses = await _expenseService.getAllTimeTotalExpenses(
        userId,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('HistoryProvider: Error fetching totals: $e');
    }
  }

  /// Refresh all-time data.
  Future<void> refresh(String userId) async {
    await SyncService().immediateSync(userId);
    await _fetchAllTimeTotals(userId);
  }

  @override
  void dispose() {
    _historySub?.cancel();
    _expensesSub?.cancel();
    _totalsSub?.cancel();
    super.dispose();
  }
}
