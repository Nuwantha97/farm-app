import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/hive_service.dart';
import '../../../models/expense_model.dart';

/// Hive-based expense CRUD service.
/// All data is stored locally in an encrypted Hive box.
class ExpenseService {
  /// Keep summaries current after local edits, archiving, or a cloud pull.
  Stream<({double expenses, double income})> watchTotals(
    String userId, {
    bool allTime = false,
  }) =>
      _watchBoxes([
        HiveService.cropsBox,
        HiveService.cropHistoryBox,
        HiveService.expensesBox,
        HiveService.commonExpensesBox,
        HiveService.commonExpenseHistoryBox,
        if (allTime) HiveService.expenseHistoryBox,
      ]).asyncMap(
        (_) async => (
          expenses: await (allTime
              ? getAllTimeTotalExpenses(userId)
              : getTotalExpenses(userId)),
          income: await (allTime
              ? getAllTimeTotalIncome(userId)
              : getTotalIncome(userId)),
        ),
      );

  Stream<void> _watchBoxes(List<Box<Map>> boxes) {
    final subscriptions = <StreamSubscription<BoxEvent>>[];
    final changes = StreamController<void>();
    changes.onListen = () {
      for (final box in boxes) {
        subscriptions.add(box.watch().listen((_) => changes.add(null)));
      }
      changes.add(null);
    };
    changes.onCancel = () async {
      await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()),
      );
    };
    return changes.stream;
  }

  bool _isArchived(String key, Map data) =>
      data['isArchived'] == true ||
      data['archivedAt'] != null ||
      HiveService.cropHistoryBox.containsKey(key);

  static const _uuid = Uuid();

  /// Hive key for crop expenses: {userId}_{cropId}_{expenseId}
  String _cropExpenseKey(String userId, String cropId, String expenseId) =>
      '${userId}_${cropId}_$expenseId';

  String? _legacyExpenseCropId(String userId, String cropId) =>
      HiveService.cropsBox.get('${userId}_$cropId')?['firebaseId'] as String?;

  /// Hive key for common expenses: {userId}_common_{expenseId}
  String _commonExpenseKey(String userId, String expenseId) =>
      '${userId}_common_$expenseId';

  /// Capture crop expenses before moving the crop, preserving older snapshots.
  static Future<void> snapshotCropExpenses(
    String userId,
    String cropId,
    Map crop,
    String archivedAt,
  ) async {
    final prefix = '${userId}_${cropId}_';
    final firebaseId = crop['firebaseId'];
    final legacyPrefix = firebaseId is String
        ? '${userId}_${firebaseId}_'
        : prefix;
    final history = HiveService.expenseHistoryBox;
    final snapshots = <String, Map>{};
    for (final entry in HiveService.getItemsByUser(
      HiveService.expensesBox,
      userId,
    )) {
      if (!entry.key.startsWith(prefix) && !entry.key.startsWith(legacyPrefix)) {
        continue;
      }
      final data = entry.value;
      if (data['syncStatus'] == 'deleted') continue;
      final sourcePrefix = entry.key.startsWith(prefix) ? prefix : legacyPrefix;
      final id =
          data['localId'] ??
          data['id'] ??
          entry.key.substring(sourcePrefix.length);
      final key = '$prefix$id';
      final legacyKey = '$legacyPrefix$id';
      if (history.containsKey(key) || history.containsKey(legacyKey)) continue;
      snapshots[key] = {
        ...data,
        'localId': id,
        'cropId': cropId,
        'cropName': crop['name'] ?? data['cropName'],
        'archivedAt': archivedAt,
      };
    }
    await history.putAll(snapshots);
  }

  /// Add an expense to a specific crop.
  Future<void> addCropExpense(
    String userId,
    String cropId,
    Expense expense,
  ) async {
    final cropKey = '${userId}_$cropId';
    final crop = HiveService.cropsBox.get(cropKey);
    if (crop == null ||
        crop['syncStatus'] == 'deleted' ||
        _isArchived(cropKey, crop)) {
      throw StateError('This crop is no longer in the current list.');
    }
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
  Stream<List<Expense>> getCropExpenses(String userId, String cropId) =>
      getCurrentCropExpenses(userId).map(
        (expenses) =>
            expenses.where((expense) => expense.cropId == cropId).toList(),
      );

  Stream<List<Expense>> getCurrentCropExpenses(String userId) => _watchBoxes([
    HiveService.cropsBox,
    HiveService.cropHistoryBox,
    HiveService.expensesBox,
  ]).map((_) => _cropExpenses(userId, archived: false));

  /// Get all common expenses as a stream.
  Stream<List<Expense>> getCommonExpenses(String userId) => _watchBoxes([
    HiveService.commonExpensesBox,
    HiveService.commonExpenseHistoryBox,
  ]).map((_) => _getCommonExpensesList(userId));

  List<Expense> _getCommonExpensesList(String userId, {bool archived = false}) {
    final prefix = '${userId}_common_';
    final box = archived
        ? HiveService.commonExpenseHistoryBox
        : HiveService.commonExpensesBox;
    final expenses = box
        .toMap()
        .entries
        .where(
          (e) =>
              e.key.toString().startsWith(prefix) &&
              (archived ||
                  !HiveService.commonExpenseHistoryBox.containsKey(e.key)),
        )
        .map((e) => Expense.fromMap(Map<String, dynamic>.from(e.value)))
        .where((e) => e.syncStatus != 'deleted')
        .toList();

    expenses.sort((a, b) => b.date.compareTo(a.date));
    return expenses;
  }

  Stream<({List<Expense> common, List<Expense> crops})> watchArchivedExpenses(
    String userId,
  ) =>
      _watchBoxes([
        HiveService.cropsBox,
        HiveService.cropHistoryBox,
        HiveService.expensesBox,
        HiveService.expenseHistoryBox,
        HiveService.commonExpenseHistoryBox,
      ]).map(
        (_) => (
          common: _getCommonExpensesList(userId, archived: true),
          crops: _cropExpenses(userId, archived: true),
        ),
      );

  List<Expense> _cropExpenses(String userId, {required bool archived}) {
    final crops = <String, ({String id, String? name})>{};
    final prefix = '${userId}_';
    final current = HiveService.getItemsByUser(HiveService.cropsBox, userId);
    final history = HiveService.getItemsByUser(
      HiveService.cropHistoryBox,
      userId,
    );
    for (final entry in [...current, if (archived) ...history]) {
      final data = entry.value;
      if (data['syncStatus'] == 'deleted' ||
          _isArchived(entry.key, data) != archived) {
        continue;
      }
      final id = entry.key.substring(prefix.length);
      final crop = (id: id, name: data['name'] as String?);
      crops[id] = crop;
      final firebaseId = data['firebaseId'];
      if (firebaseId is String && firebaseId != id) crops[firebaseId] = crop;
    }

    final byId = <(String, String), Expense>{};
    for (final box in [
      HiveService.expensesBox,
      if (archived) HiveService.expenseHistoryBox,
    ]) {
      for (final entry in HiveService.getItemsByUser(box, userId)) {
        final data = entry.value;
        if (data['syncStatus'] == 'deleted') continue;
        final key = entry.key.substring(prefix.length);
        final expenseId = data['localId'] as String? ?? data['id'] as String?;
        final suffix = expenseId == null
            ? -1
            : key.length - expenseId.length - 1;
        final split = suffix > 0 && key.endsWith('_$expenseId')
            ? suffix
            : key.lastIndexOf('_');
        if (split <= 0) continue;
        final crop = crops[key.substring(0, split)] ?? crops[data['cropId']];
        if (crop == null) continue;
        final id = expenseId ?? key.substring(split + 1);
        byId[(crop.id, id)] = Expense.fromMap({
          ...data,
          'localId': id,
          'cropId': crop.id,
          'cropName': crop.name ?? data['cropName'],
        });
      }
    }
    return byId.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Delete a crop expense.
  Future<void> deleteCropExpense(
    String userId,
    String cropId,
    String expenseId,
  ) async {
    var key = _cropExpenseKey(userId, cropId, expenseId);
    final legacyCropId = _legacyExpenseCropId(userId, cropId);
    if (legacyCropId != null && !HiveService.expensesBox.containsKey(key)) {
      key = _cropExpenseKey(userId, legacyCropId, expenseId);
    }
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

  /// Save an archive copy before hiding the current row.
  Future<bool> archiveCommonExpense(String userId, String expenseId) async {
    final key = _commonExpenseKey(userId, expenseId);
    if (HiveService.commonExpenseHistoryBox.containsKey(key)) return true;
    final existing = HiveService.commonExpensesBox.get(key);
    if (existing == null || existing['syncStatus'] == 'deleted') return false;
    final now = DateTime.now().toIso8601String();
    await HiveService.commonExpenseHistoryBox.put(key, {
      ...existing,
      'localId': expenseId,
      'archivedAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
    });
    return true;
  }

  /// Get total income from active (non-archived) sold and consumed crops only.
  Future<double> getTotalIncome(String userId) async {
    double total = 0.0;
    final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);

    for (final entry in entries) {
      final data = Map<String, dynamic>.from(entry.value);
      final status = data['status'] ?? '';
      if (data['syncStatus'] == 'deleted') continue;
      if (_isArchived(entry.key, data)) continue;

      if (status == 'sold') {
        total += (data['soldAmount'] ?? 0.0).toDouble();
      } else if (status == 'consumed') {
        total += (data['consumedEstimatedAmount'] ?? 0.0).toDouble();
      }
    }
    return total;
  }

  /// Get income entries (sold/consumed crops) as a stream — active only.
  Stream<List<Map<String, dynamic>>> getIncomeEntries(String userId) =>
      _watchBoxes([HiveService.cropsBox, HiveService.cropHistoryBox])
          .map((_) => _getIncomeEntriesList(userId));

  List<Map<String, dynamic>> _getIncomeEntriesList(String userId) {
    final entries = HiveService.getItemsByUser(HiveService.cropsBox, userId);
    return entries
        .where((entry) => !_isArchived(entry.key, entry.value))
        .map((e) => Map<String, dynamic>.from(e.value))
        .where((data) {
          final status = data['status'] ?? '';
          return (status == 'sold' || status == 'consumed') &&
              data['syncStatus'] != 'deleted' &&
              data['isArchived'] != true;
        })
        .map((data) {
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
        })
        .toList();
  }

  /// Total for the current lists.
  Future<double> getTotalExpenses(String userId) async =>
      _sumExpenses(_getCommonExpensesList(userId)) +
      _sumExpenses(_cropExpenses(userId, archived: false));

  /// Current and archived amounts, counting each expense once.
  Future<double> getAllTimeTotalExpenses(String userId) async =>
      _sumExpenses(_getCommonExpensesList(userId)) +
      _sumExpenses(_getCommonExpensesList(userId, archived: true)) +
      _sumExpenses(_cropExpenses(userId, archived: false)) +
      _sumExpenses(_cropExpenses(userId, archived: true));

  double _sumExpenses(List<Expense> expenses) =>
      expenses.fold(0.0, (total, expense) => total + expense.amount);

  /// Get all-time total income (active + archived crops).
  Future<double> getAllTimeTotalIncome(String userId) async {
    double total = 0.0;

    // Active crops
    final activeEntries = HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    );
    for (final entry in activeEntries) {
      if (HiveService.cropHistoryBox.containsKey(entry.key)) continue;
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
    final activeEntries = HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    );
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
    final historyEntries = HiveService.getItemsByUser(
      HiveService.cropHistoryBox,
      userId,
    );
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
