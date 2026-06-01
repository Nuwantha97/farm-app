import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/services/sync_service.dart';
import '../../../models/expense_model.dart';
import '../services/expense_service.dart';

class FinanceProvider extends ChangeNotifier {
  final ExpenseService _service = ExpenseService();

  List<Expense> _commonExpenses = [];
  List<Expense> _cropExpenses = [];
  List<Map<String, dynamic>> _incomeEntries = [];
  String? _errorMessage;
  double _totalExpenses = 0.0;
  double _totalIncome = 0.0;

  StreamSubscription<List<Expense>>? _commonSub;
  StreamSubscription<List<Expense>>? _cropSub;
  StreamSubscription<List<Map<String, dynamic>>>? _incomeSub;

  List<Expense> get commonExpenses => _commonExpenses;
  List<Expense> get cropExpenses => _cropExpenses;
  List<Expense> get allExpenses => [..._commonExpenses, ..._cropExpenses];
  List<Map<String, dynamic>> get incomeEntries => _incomeEntries;
  String? get errorMessage => _errorMessage;
  double get totalExpenses => _totalExpenses;
  double get totalIncome => _totalIncome;
  double get totalProfit => _totalIncome - _totalExpenses;

  /// Load common expenses.
  void loadCommonExpenses(String userId) {
    _commonSub?.cancel();
    _commonSub = _service.getCommonExpenses(userId).listen(
      (expenses) {
        _commonExpenses = expenses;
        _calculateTotal();
        notifyListeners();
      },
      onError: (e) {
        _errorMessage = 'Failed to load expenses';
        notifyListeners();
      },
    );

    // Fetch from Firebase in background (if sync enabled)
    SyncService().backgroundPull(userId);
  }

  /// Load crop expenses for a specific crop.
  void loadCropExpenses(String userId, String cropId, {String? cropName}) {
    _cropSub?.cancel();
    _cropSub =
        _service.getCropExpenses(userId, cropId, cropName: cropName).listen(
      (expenses) {
        _cropExpenses = expenses;
        _calculateTotal();
        notifyListeners();
      },
      onError: (e) {
        _errorMessage = 'Failed to load crop expenses';
        notifyListeners();
      },
    );

    // Fetch from Firebase in background (if sync enabled)
    SyncService().backgroundPull(userId);
  }

  /// Load income entries (sold/consumed crops).
  void loadIncomeEntries(String userId) {
    _incomeSub?.cancel();
    _incomeSub = _service.getIncomeEntries(userId).listen(
      (entries) {
        _incomeEntries = entries;
        notifyListeners();
      },
      onError: (e) {
        _errorMessage = 'Failed to load income entries';
        notifyListeners();
      },
    );

    // Fetch from Firebase in background (if sync enabled)
    SyncService().backgroundPull(userId);
  }

  /// Fetch total expenses.
  Future<void> fetchTotalExpenses(String userId) async {
    try {
      _totalExpenses = await _service.getTotalExpenses(userId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to calculate total';
      notifyListeners();
    }
  }

  /// Fetch total income.
  Future<void> fetchTotalIncome(String userId) async {
    try {
      _totalIncome = await _service.getTotalIncome(userId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to calculate income';
      notifyListeners();
    }
  }

  Future<bool> addCropExpense(
      String userId, String cropId, Expense expense) async {
    try {
      await _service.addCropExpense(userId, cropId, expense);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add expense';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addCommonExpense(String userId, Expense expense) async {
    try {
      await _service.addCommonExpense(userId, expense);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add expense';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCropExpense(
      String userId, String cropId, String expenseId) async {
    try {
      await _service.deleteCropExpense(userId, cropId, expenseId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete expense';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCommonExpense(String userId, String expenseId) async {
    try {
      await _service.deleteCommonExpense(userId, expenseId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete expense';
      notifyListeners();
      return false;
    }
  }

  void _calculateTotal() {
    _totalExpenses = 0.0;
    for (var e in _commonExpenses) {
      _totalExpenses += e.amount;
    }
    for (var e in _cropExpenses) {
      _totalExpenses += e.amount;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _commonSub?.cancel();
    _cropSub?.cancel();
    _incomeSub?.cancel();
    super.dispose();
  }
}
