import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/expense_model.dart';

class ExpenseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Add an expense to a specific crop
  Future<void> addCropExpense(
      String userId, String cropId, Expense expense) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('crops')
        .doc(cropId)
        .collection('expenses')
        .add(expense.toMap());
  }

  /// Add a common expense (not linked to any crop)
  Future<void> addCommonExpense(String userId, Expense expense) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('common_expenses')
        .add(expense.toMap());
  }

  /// Get all expenses for a specific crop as a stream
  Stream<List<Expense>> getCropExpenses(String userId, String cropId, {String? cropName}) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('crops')
        .doc(cropId)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Expense.fromFirestore(doc, cropId: cropId, cropName: cropName))
            .toList());
  }

  /// Get all common expenses as a stream
  Stream<List<Expense>> getCommonExpenses(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('common_expenses')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Expense.fromFirestore(doc)).toList());
  }

  /// Delete a crop expense
  Future<void> deleteCropExpense(
      String userId, String cropId, String expenseId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('crops')
        .doc(cropId)
        .collection('expenses')
        .doc(expenseId)
        .delete();
  }

  /// Delete a common expense
  Future<void> deleteCommonExpense(String userId, String expenseId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('common_expenses')
        .doc(expenseId)
        .delete();
  }

  /// Get total income from sold and consumed crops
  Future<double> getTotalIncome(String userId) async {
    double total = 0.0;

    final cropsRef = _db.collection('users').doc(userId).collection('crops');

    // Sum soldAmount from crops with status 'sold'
    final soldSnap = await cropsRef
        .where('status', isEqualTo: 'sold')
        .get();
    for (var doc in soldSnap.docs) {
      final data = doc.data();
      total += (data['soldAmount'] ?? 0.0).toDouble();
    }

    // Sum consumedEstimatedAmount from crops with status 'consumed'
    final consumedSnap = await cropsRef
        .where('status', isEqualTo: 'consumed')
        .get();
    for (var doc in consumedSnap.docs) {
      final data = doc.data();
      total += (data['consumedEstimatedAmount'] ?? 0.0).toDouble();
    }

    return total;
  }

  /// Get income entries (sold/consumed crops) as a stream
  Stream<List<Map<String, dynamic>>> getIncomeEntries(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('crops')
        .where('status', whereIn: ['sold', 'consumed'])
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              final status = data['status'] ?? '';
              return {
                'id': doc.id,
                'name': data['name'] ?? '',
                'status': status,
                'amount': status == 'sold'
                    ? (data['soldAmount'] ?? 0.0).toDouble()
                    : (data['consumedEstimatedAmount'] ?? 0.0).toDouble(),
                'date': data['harvestedDate'] != null
                    ? (data['harvestedDate'] as Timestamp).toDate()
                    : (data['createdAt'] as Timestamp?)?.toDate() ??
                        DateTime.now(),
              };
            }).toList());
  }

  /// Get total expenses for a user (all crops + common)
  Future<double> getTotalExpenses(String userId) async {
    double total = 0.0;

    // Common expenses
    final commonSnap = await _db
        .collection('users')
        .doc(userId)
        .collection('common_expenses')
        .get();
    for (var doc in commonSnap.docs) {
      total += (doc.data()['amount'] ?? 0.0).toDouble();
    }

    // Crop expenses
    final cropsSnap = await _db
        .collection('users')
        .doc(userId)
        .collection('crops')
        .get();
    for (var cropDoc in cropsSnap.docs) {
      final expSnap = await cropDoc.reference.collection('expenses').get();
      for (var doc in expSnap.docs) {
        total += (doc.data()['amount'] ?? 0.0).toDouble();
      }
    }

    return total;
  }
}
