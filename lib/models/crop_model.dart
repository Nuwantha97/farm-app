import 'package:cloud_firestore/cloud_firestore.dart';

class Crop {
  final String id;
  final String name;
  final String type;
  final String status; // 'active', 'harvested', 'planning'
  final DateTime? plantedDate;
  final double area; // in acres or hectares
  final String notes;
  final DateTime createdAt;

  Crop({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    this.plantedDate,
    this.area = 0.0,
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Crop.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Crop(
      id: doc.id,
      name: data['name'] ?? '',
      type: data['type'] ?? '',
      status: data['status'] ?? 'planning',
      plantedDate: data['plantedDate'] != null
          ? (data['plantedDate'] as Timestamp).toDate()
          : null,
      area: (data['area'] ?? 0.0).toDouble(),
      notes: data['notes'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'status': status,
      'plantedDate':
          plantedDate != null ? Timestamp.fromDate(plantedDate!) : null,
      'area': area,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Crop copyWith({
    String? id,
    String? name,
    String? type,
    String? status,
    DateTime? plantedDate,
    double? area,
    String? notes,
  }) {
    return Crop(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      status: status ?? this.status,
      plantedDate: plantedDate ?? this.plantedDate,
      area: area ?? this.area,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}
