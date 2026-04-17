import 'package:cloud_firestore/cloud_firestore.dart';

class Sale {
  final String id;
  final String cropId;
  final String cropName;
  final double amount;
  final double quantity;
  final String unit; // 'kg', 'ton', 'bushel', etc.
  final String buyer;
  final DateTime date;
  final String notes;
  final DateTime createdAt;

  Sale({
    required this.id,
    required this.cropId,
    required this.cropName,
    required this.amount,
    required this.quantity,
    this.unit = 'kg',
    this.buyer = '',
    required this.date,
    this.notes = '',
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
      buyer: data['buyer'] ?? '',
      date: data['date'] != null
          ? (data['date'] as Timestamp).toDate()
          : DateTime.now(),
      notes: data['notes'] ?? '',
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
      'buyer': buyer,
      'date': Timestamp.fromDate(date),
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
