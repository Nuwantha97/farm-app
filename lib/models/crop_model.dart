import 'package:cloud_firestore/cloud_firestore.dart';

class Crop {
  final String id;
  final String name;
  final String status; // 'growing', 'harvested', 'planning'
  final DateTime? plantedDate;
  final DateTime createdAt;

  Crop({
    required this.id,
    required this.name,
    required this.status,
    this.plantedDate,
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
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Crop copyWith({
    String? id,
    String? name,
    String? status,
    DateTime? plantedDate,
  }) {
    return Crop(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      plantedDate: plantedDate ?? this.plantedDate,
      createdAt: createdAt,
    );
  }
}
