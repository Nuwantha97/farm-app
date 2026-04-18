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

  Sale({
    required this.id,
    required this.cropId,
    required this.cropName,
    required this.amount,
    required this.quantity,
    this.unit = 'kg',
    required this.date,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

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
    };
  }
}
