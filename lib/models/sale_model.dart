import 'package:cloud_firestore/cloud_firestore.dart';

class Sale {
  final String id;
  final String cropId;
  final String cropName;
  final double amount;
  final double quantity;
  final String unit; // 'kg', 'ton', 'bushel', etc.
  final DateTime date;
  final DateTime createdAt;

  // Sync tracking fields
  final String syncStatus;
  final DateTime updatedAt;
  final String localId;
  final String? firebaseId;

  Sale({
    required this.id,
    required this.cropId,
    required this.cropName,
    required this.amount,
    required this.quantity,
    this.unit = 'kg',
    required this.date,
    DateTime? createdAt,
    this.syncStatus = 'pending',
    DateTime? updatedAt,
    String? localId,
    this.firebaseId,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        localId = localId ?? id;

  factory Sale.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Sale(
      id: doc.id,
      cropId: data['cropId'] ?? '',
      cropName: data['cropName'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      quantity: (data['quantity'] ?? 0.0).toDouble(),
      unit: data['unit'] ?? 'kg',
      date: data['date'] != null
          ? (data['date'] as Timestamp).toDate()
          : DateTime.now(),
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

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] ?? '',
      cropId: map['cropId'] ?? '',
      cropName: map['cropName'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      quantity: (map['quantity'] ?? 0.0).toDouble(),
      unit: map['unit'] ?? 'kg',
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
      createdAt:
          map['createdAt'] != null ? DateTime.parse(map['createdAt']) : null,
      syncStatus: map['syncStatus'] ?? 'pending',
      updatedAt:
          map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
      localId: map['localId'],
      firebaseId: map['firebaseId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cropId': cropId,
      'cropName': cropName,
      'amount': amount,
      'quantity': quantity,
      'unit': unit,
      'date': Timestamp.fromDate(date),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'localId': localId,
    };
  }

  Map<String, dynamic> toHiveMap() {
    return {
      'id': id,
      'cropId': cropId,
      'cropName': cropName,
      'amount': amount,
      'quantity': quantity,
      'unit': unit,
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'syncStatus': syncStatus,
      'updatedAt': updatedAt.toIso8601String(),
      'localId': localId,
      'firebaseId': firebaseId,
    };
  }
}
