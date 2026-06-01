import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final String? cropId; // null for common expenses
  final String? cropName; // denormalized for display
  final DateTime createdAt;

  // Sync tracking fields
  final String syncStatus; // 'pending', 'synced', 'modified', 'deleted'
  final DateTime updatedAt;
  final String localId; // UUID for local identity
  final String? firebaseId; // Firestore document ID

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    this.cropId,
    this.cropName,
    DateTime? createdAt,
    this.syncStatus = 'pending',
    DateTime? updatedAt,
    String? localId,
    this.firebaseId,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        localId = localId ?? id;

  bool get isCommonExpense => cropId == null;

  /// Deserialize from Firestore document (used for sync pull).
  factory Expense.fromFirestore(
    DocumentSnapshot doc, {
    String? cropId,
    String? cropName,
  }) {
    final data = doc.data() as Map<String, dynamic>;
    return Expense(
      id: doc.id,
      title: data['title'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      date: data['date'] != null
          ? (data['date'] as Timestamp).toDate()
          : DateTime.now(),
      cropId: cropId ?? data['cropId'],
      cropName: cropName ?? data['cropName'],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      syncStatus: 'synced',
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      localId: data['localId'] ?? doc.id,
      firebaseId: doc.id,
    );
  }

  /// Deserialize from Hive map (uses ISO date strings).
  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
      cropId: map['cropId'],
      cropName: map['cropName'],
      createdAt:
          map['createdAt'] != null ? DateTime.parse(map['createdAt']) : null,
      syncStatus: map['syncStatus'] ?? 'pending',
      updatedAt:
          map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
      localId: map['localId'],
      firebaseId: map['firebaseId'],
    );
  }

  /// Serialize for Firestore (used for sync push).
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'cropId': cropId,
      'cropName': cropName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'localId': localId,
    };
  }

  /// Serialize for Hive storage (uses ISO date strings).
  Map<String, dynamic> toHiveMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'date': date.toIso8601String(),
      'cropId': cropId,
      'cropName': cropName,
      'createdAt': createdAt.toIso8601String(),
      'syncStatus': syncStatus,
      'updatedAt': updatedAt.toIso8601String(),
      'localId': localId,
      'firebaseId': firebaseId,
    };
  }
}
