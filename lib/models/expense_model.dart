import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final String category; // 'labor', 'fertilizer', 'seeds', 'equipment', 'other'
  final String notes;
  final String? cropId; // null for common expenses
  final String? cropName; // denormalized for display
  final DateTime createdAt;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
    this.notes = '',
    this.cropId,
    this.cropName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isCommonExpense => cropId == null;

  factory Expense.fromFirestore(DocumentSnapshot doc, {String? cropId, String? cropName}) {
    final data = doc.data() as Map<String, dynamic>;
    return Expense(
      id: doc.id,
      title: data['title'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      date: data['date'] != null
          ? (data['date'] as Timestamp).toDate()
          : DateTime.now(),
      category: data['category'] ?? 'other',
      notes: data['notes'] ?? '',
      cropId: cropId ?? data['cropId'],
      cropName: cropName ?? data['cropName'],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'category': category,
      'notes': notes,
      'cropId': cropId,
      'cropName': cropName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
