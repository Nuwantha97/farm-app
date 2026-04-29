import 'package:cloud_firestore/cloud_firestore.dart';

class Crop {
  final String id;
  final String name;
  final String status; // 'planning', 'planted', 'growing', 'harvested', 'sold', 'consumed'
  final DateTime? plantedDate;
  final DateTime? harvestedDate;
  final double? soldAmount;
  final double? consumedEstimatedAmount;
  final DateTime createdAt;

  Crop({
    required this.id,
    required this.name,
    required this.status,
    this.plantedDate,
    this.harvestedDate,
    this.soldAmount,
    this.consumedEstimatedAmount,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Crop.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Crop(
      id: doc.id,
      name: data['name'] ?? '',
      status: data['status'] ?? 'planning',
      plantedDate: data['plantedDate'] != null
          ? (data['plantedDate'] as Timestamp).toDate()
          : null,
      harvestedDate: data['harvestedDate'] != null
          ? (data['harvestedDate'] as Timestamp).toDate()
          : null,
      soldAmount: data['soldAmount'] != null
          ? (data['soldAmount'] as num).toDouble()
          : null,
      consumedEstimatedAmount: data['consumedEstimatedAmount'] != null
          ? (data['consumedEstimatedAmount'] as num).toDouble()
          : null,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'status': status,
      'plantedDate': plantedDate != null
          ? Timestamp.fromDate(plantedDate!)
          : null,
      'harvestedDate': harvestedDate != null
          ? Timestamp.fromDate(harvestedDate!)
          : null,
      'soldAmount': soldAmount,
      'consumedEstimatedAmount': consumedEstimatedAmount,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Crop copyWith({
    String? id,
    String? name,
    String? status,
    DateTime? plantedDate,
    DateTime? harvestedDate,
    double? soldAmount,
    double? consumedEstimatedAmount,
  }) {
    return Crop(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      plantedDate: plantedDate ?? this.plantedDate,
      harvestedDate: harvestedDate ?? this.harvestedDate,
      soldAmount: soldAmount ?? this.soldAmount,
      consumedEstimatedAmount: consumedEstimatedAmount ?? this.consumedEstimatedAmount,
      createdAt: createdAt,
    );
  }
}
