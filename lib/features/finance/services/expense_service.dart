import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/hive_service.dart';
import '../../../models/expense_model.dart';

/// Hive-based expense CRUD service.
/// All data is stored locally in an encrypted Hive box.
class ExpenseService {
  static const _uuid = Uuid();

  /// Hive key for crop expenses: {userId}_{cropId}_{expenseId}
  String _cropExpenseKey(String userId, String cropId, String expenseId) =>
      '${userId}_${cropId}_$expenseId';

  /// Hive key for common expenses: {userId}_common_{expenseId}
  String _commonExpenseKey(String userId, String expenseId) =>
      '${userId}_common_$expenseId';

  /// Add an expense to a specific crop.
  Future<void> addCropExpense(
      String userId, String cropId, Expense expense) async {
    final expenseId = _uuid.v4();
    final newExpense = Expense(
      id: expenseId,
      title: expense.title,
      amount: expense.amount,
      date: expense.date,
      cropId: cropId,
      cropName: expense.cropName,
      syncStatus: 'pending',
      localId: expenseId,
    );

    await HiveService.expensesBox.put(
      _cropExpenseKey(userId, cropId, expenseId),
      Map<String, dynamic>.from(newExpense.toHiveMap()),
    );
    debugPrint('ExpenseService: Added crop expense $expenseId');
  }

  /// Add a common expense (not linked to any crop).
  Future<void> addCommonExpense(String userId, Expense expense) async {
    final expenseId = _uuid.v4();
    final newExpense = Expense(
      id: expenseId,
      title: expense.title,
      amount: expense.amount,
      date: expense.date,
      syncStatus: 'pending',
      localId: expenseId,
    );

    await HiveService.commonExpensesBox.put(
      _commonExpenseKey(userId, expenseId),
      Map<String, dynamic>.from(newExpense.toHiveMap()),
    );
    debugPrint('ExpenseService: Added common expense $expenseId');
  }

  /// Get all expenses for a specific crop as a stream.
  Stream<List<Expense>> getCropExpenses(String userId, String cropId,
      {String? cropName}) {
    final controller = StreamController<List<Expense>>();
    controller.add(_getCropExpensesList(userId, cropId, cropName: cropName));

    void listener() {
      if (!controller.isClosed) {
        controller
            .add(_getCropExpensesList(userId, cropId, cropName: cropName));
      }
    }

    HiveService.expensesBox.listenable().addListener(listener);
    controller.onCancel = () {
      HiveService.expensesBox.listenable().removeListener(listener);
    };

    return controller.stream;
  }

  List<Expense> _getCropExpensesList(String userId, String cropId,
      {String? cropName}) {
    final prefix = '${userId}_${cropId}_';
    final expenses = HiveService.expensesBox
        .toMap()
        .entries
        .where((e) => e.key.toString().startsWith(prefix))
        .map((e) {
      final data = Map<String, dynamic>.from(e.value);
      if (cropName != null) data['cropName'] = cropName;
      if (data['cropId'] == null) data['cropId'] = cropId;
      return Expense.fromMap(data);
    })
        .where((e) => e.syncStatus != 'deleted')
        .toList();

    expenses.sort((a, b) => b.date.compareTo(a.date));
    return expenses;
  }

  /// Get all common expenses as a stream.
  Stream<List<Expense>> getCommonExpenses(String userId) {
    final controller = StreamController<List<Expense>>();
    controller.add(_getCommonExpensesList(userId));

    void listener() {
      if (!controller.isClosed) {
        controller.add(_getCommonExpensesList(userId));
      }
    }

    HiveService.commonExpensesBox.listenable().addListener(listener);
    controller.onCancel = () {
      HiveService.commonExpensesBox.listenable().removeListener(listener);
    };

    return controller.stream;
  }

  List<Expense> _getCommonExpensesList(String userId) {
    final prefix = '${userId}_common_';
    final expenses = HiveService.commonExpensesBox
        .toMap()
        .entries
        .where((e) => e.key.toString().startsWith(prefix))
        .map((e) => Expense.fromMap(Map<String, dynamic>.from(e.value)))
        .where((e) => e.syncStatus != 'deleted')
        .toList();

    expenses.sort((a, b) => b.date.compareTo(a.date));
    return expenses;
  }

  /// Delete a crop expense.
  Future<void> deleteCropExpense(
      String userId, String cropId, String expenseId) async {
    final key = _cropExpenseKey(userId, cropId, expenseId);
    final existing = HiveService.expensesBox.get(key);

    if (existing != null) {
      final data = Map<String, dynamic>.from(existing);
      if (data['firebaseId'] != null) {
        data['syncStatus'] = 'deleted';
        data['updatedAt'] = DateTime.now().toIso8601String();
        await HiveService.expensesBox.put(key, Map<String, dynamic>.from(data));
      } else {
        await HiveService.expensesBox.delete(key);
      }
    }
  }

  /// Delete a common expense.
  Future<void> deleteCommonExpense(String userId, String expenseId) async {
    final key = _commonExpenseKey(userId, expenseId);
    final existing = HiveService.commonExpensesBox.get(key);

    if (existing != null) {
      final data = Map<String, dynamic>.from(existing);
      if (data['firebaseId'] != null) {
        data['syncStatus'] = 'deleted';
        data['updatedAt'] = DateTime.now().toIso8601String();
        await HiveService.commonExpensesBox
            .put(key, Map<String, dynamic>.from(data));
      } else {
        await HiveService.commonExpensesBox.delete(key);
      }
    }
  }

  /// Get total income from active (non-archived) sold and consumed crops only.
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

  /// Get income entries (sold/consumed crops) as a stream — active only.
  Stream<List<Map<String, dynamic>>> getIncomeEntries(String userId) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    controller.add(_getIncomeEntriesList(userId));

    void listener() {
      if (!controller.isClosed) {
        controller.add(_getIncomeEntriesList(userId));
      }
    }

    HiveService.cropsBox.listenable().addListener(listener);
    controller.onCancel = () {
      HiveService.cropsBox.listenable().removeListener(listener);
    };

    return controller.stream;
  }

  List<Map<String, dynamic>> _getIncomeEntriesList(String userId) {
    final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);
    return entries
        .map((e) => Map<String, dynamic>.from(e.value))
        .where((data) {
      final status = data['status'] ?? '';
      return (status == 'sold' || status == 'consumed') &&
          data['syncStatus'] != 'deleted' &&
          data['isArchived'] != true;
    }).map((data) {
      final status = data['status'] ?? '';
      return {
        'id': data['id'] ?? '',
        'name': data['name'] ?? '',
        'status': status,
        'amount': status == 'sold'
            ? (data['soldAmount'] ?? 0.0).toDouble()
            : (data['consumedEstimatedAmount'] ?? 0.0).toDouble(),
        'date': data['harvestedDate'] != null
            ? DateTime.parse(data['harvestedDate'])
            : (data['createdAt'] != null
                ? DateTime.parse(data['createdAt'])
                : DateTime.now()),
      };
    }).toList();
  }

  /// Get total expenses for a user — active crops only + common expenses.
  /// Excludes expenses for archived crops.
  Future<double> getTotalExpenses(String userId) async {
    double total = 0.0;

    // Common expenses (always count)
    final commonPrefix = '${userId}_common_';
    for (final entry in HiveService.commonExpensesBox.toMap().entries) {
      if (!entry.key.toString().startsWith(commonPrefix)) continue;
      final data = Map<String, dynamic>.from(entry.value);
      if (data['syncStatus'] == 'deleted') continue;
      total += (data['amount'] ?? 0.0).toDouble();
    }

    // Get active (non-archived) crop IDs
    final activeCropIds = <String>{};
    final cropEntries =
        HiveService.getItemsByUser(HiveService.cropsBox, userId);
    for (final entry in cropEntries) {
      final data = Map<String, dynamic>.from(entry.value);
      if (data['syncStatus'] == 'deleted') continue;
      if (data['isArchived'] == true) continue;
      final cropId = data['id'] ?? data['localId'] ?? '';
      if (cropId.isNotEmpty) activeCropIds.add(cropId);
    }

    // Crop expenses — only for active crops
    final userPrefix = '${userId}_';
    for (final entry in HiveService.expensesBox.toMap().entries) {
      final key = entry.key.toString();
      if (!key.startsWith(userPrefix)) continue;
      final data = Map<String, dynamic>.from(entry.value);
      if (data['syncStatus'] == 'deleted') continue;

      // Extract cropId from key: {userId}_{cropId}_{expenseId}
      final withoutUser = key.substring(userPrefix.length);
      final lastUnderscore = withoutUser.lastIndexOf('_');
      if (lastUnderscore <= 0) continue;
      final cropId = withoutUser.substring(0, lastUnderscore);

      if (activeCropIds.contains(cropId)) {
        total += (data['amount'] ?? 0.0).toDouble();
      }
    }

    return total;
  }

  // ── History methods ──────────────────────────────────────────

  /// Get all-time total expenses (active + archived crops + common).
  Future<double> getAllTimeTotalExpenses(String userId) async {
    double total = 0.0;

    // Common expenses
    final commonPrefix = '${userId}_common_';
    for (final entry in HiveService.commonExpensesBox.toMap().entries) {
      if (!entry.key.toString().startsWith(commonPrefix)) continue;
      final data = Map<String, dynamic>.from(entry.value);
      if (data['syncStatus'] == 'deleted') continue;
      total += (data['amount'] ?? 0.0).toDouble();
    }

    // All crop expenses (active)
    final userPrefix = '${userId}_';
    for (final entry in HiveService.expensesBox.toMap().entries) {
      if (!entry.key.toString().startsWith(userPrefix)) continue;
      final data = Map<String, dynamic>.from(entry.value);
      if (data['syncStatus'] == 'deleted') continue;
      total += (data['amount'] ?? 0.0).toDouble();
    }

    // Archived expense history
    for (final entry in HiveService.expenseHistoryBox.toMap().entries) {
      if (!entry.key.toString().startsWith(userPrefix)) continue;
      final data = Map<String, dynamic>.from(entry.value);
      if (data['syncStatus'] == 'deleted') continue;
      total += (data['amount'] ?? 0.0).toDouble();
    }

    return total;
  }

  /// Get all-time total income (active + archived crops).
  Future<double> getAllTimeTotalIncome(String userId) async {
    double total = 0.0;

    // Active crops
    final activeEntries =
        HiveService.getItemsByUser(HiveService.cropsBox, userId);
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

    // Archived crops from history
    final historyEntries =
        HiveService.getItemsByUser(HiveService.cropHistoryBox, userId);
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

  /// Get all-time income entries (active + archived) as a stream.
  Stream<List<Map<String, dynamic>>> getAllTimeIncomeEntries(String userId) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    controller.add(_getAllTimeIncomeEntriesList(userId));

    void listener() {
      if (!controller.isClosed) {
        controller.add(_getAllTimeIncomeEntriesList(userId));
      }
    }

    HiveService.cropsBox.listenable().addListener(listener);
    HiveService.cropHistoryBox.listenable().addListener(listener);

    controller.onCancel = () {
      HiveService.cropsBox.listenable().removeListener(listener);
      HiveService.cropHistoryBox.listenable().removeListener(listener);
    };

    return controller.stream;
  }

  List<Map<String, dynamic>> _getAllTimeIncomeEntriesList(String userId) {
    final result = <Map<String, dynamic>>[];

    // Active crops
    final activeEntries =
        HiveService.getItemsByUser(HiveService.cropsBox, userId);
    for (final entry in activeEntries) {
      final data = Map<String, dynamic>.from(entry.value);
      final status = data['status'] ?? '';
      if (data['syncStatus'] == 'deleted') continue;
      if (status != 'sold' && status != 'consumed') continue;

      result.add({
        'id': data['id'] ?? '',
        'name': data['name'] ?? '',
        'status': status,
        'isArchived': data['isArchived'] == true,
        'amount': status == 'sold'
            ? (data['soldAmount'] ?? 0.0).toDouble()
            : (data['consumedEstimatedAmount'] ?? 0.0).toDouble(),
        'date': data['harvestedDate'] != null
            ? DateTime.parse(data['harvestedDate'])
            : (data['createdAt'] != null
                ? DateTime.parse(data['createdAt'])
                : DateTime.now()),
      });
    }

    // Archived crops from history
    final historyEntries =
        HiveService.getItemsByUser(HiveService.cropHistoryBox, userId);
    for (final entry in historyEntries) {
      final data = Map<String, dynamic>.from(entry.value);
      final status = data['status'] ?? '';
      if (status != 'sold' && status != 'consumed') continue;

      result.add({
        'id': data['id'] ?? '',
        'name': data['name'] ?? '',
        'status': status,
        'isArchived': true,
        'amount': status == 'sold'
            ? (data['soldAmount'] ?? 0.0).toDouble()
            : (data['consumedEstimatedAmount'] ?? 0.0).toDouble(),
        'date': data['harvestedDate'] != null
            ? DateTime.parse(data['harvestedDate'])
            : (data['createdAt'] != null
                ? DateTime.parse(data['createdAt'])
                : DateTime.now()),
      });
    }

    return result;
  }
}
