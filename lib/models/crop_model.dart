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

  // Archive tracking fields
  final bool isArchived; // true when crop is removed from active list
  final DateTime? archivedAt; // when the crop was archived

  // Sync tracking fields
  final String syncStatus; // 'pending', 'synced', 'modified', 'deleted'
  final DateTime updatedAt;
  final String localId; // UUID for local identity
  final String? firebaseId; // Firestore document ID

  Crop({
    required this.id,
    required this.name,
    required this.status,
    this.plantedDate,
    this.harvestedDate,
    this.soldAmount,
    this.consumedEstimatedAmount,
    DateTime? createdAt,
    this.isArchived = false,
    this.archivedAt,
    this.syncStatus = 'pending',
    DateTime? updatedAt,
    String? localId,
    this.firebaseId,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        localId = localId ?? id;

  /// Deserialize from Firestore document (used for sync pull).
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
      isArchived: data['isArchived'] ?? false,
      archivedAt: data['archivedAt'] != null
          ? (data['archivedAt'] as Timestamp).toDate()
          : null,
      syncStatus: 'synced',
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      localId: data['localId'] ?? doc.id,
      firebaseId: doc.id,
    );
  }

  /// Deserialize from Hive map (uses ISO date strings).
  factory Crop.fromMap(Map<String, dynamic> map) {
    return Crop(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      status: map['status'] ?? 'planning',
      plantedDate:
          map['plantedDate'] != null ? DateTime.parse(map['plantedDate']) : null,
      harvestedDate: map['harvestedDate'] != null
          ? DateTime.parse(map['harvestedDate'])
          : null,
      soldAmount: map['soldAmount'] != null
          ? (map['soldAmount'] as num).toDouble()
          : null,
      consumedEstimatedAmount: map['consumedEstimatedAmount'] != null
          ? (map['consumedEstimatedAmount'] as num).toDouble()
          : null,
      createdAt:
          map['createdAt'] != null ? DateTime.parse(map['createdAt']) : null,
      isArchived: map['isArchived'] ?? false,
      archivedAt: map['archivedAt'] != null
          ? DateTime.parse(map['archivedAt'])
          : null,
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
      'name': name,
      'status': status,
      'plantedDate':
          plantedDate != null ? Timestamp.fromDate(plantedDate!) : null,
      'harvestedDate':
          harvestedDate != null ? Timestamp.fromDate(harvestedDate!) : null,
      'soldAmount': soldAmount,
      'consumedEstimatedAmount': consumedEstimatedAmount,
      'createdAt': Timestamp.fromDate(createdAt),
      'isArchived': isArchived,
      'archivedAt':
          archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'localId': localId,
    };
  }

  /// Serialize for Hive storage (uses ISO date strings).
  Map<String, dynamic> toHiveMap() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'plantedDate': plantedDate?.toIso8601String(),
      'harvestedDate': harvestedDate?.toIso8601String(),
      'soldAmount': soldAmount,
      'consumedEstimatedAmount': consumedEstimatedAmount,
      'createdAt': createdAt.toIso8601String(),
      'isArchived': isArchived,
      'archivedAt': archivedAt?.toIso8601String(),
      'syncStatus': syncStatus,
      'updatedAt': updatedAt.toIso8601String(),
      'localId': localId,
      'firebaseId': firebaseId,
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
    bool? isArchived,
    DateTime? archivedAt,
    String? syncStatus,
    DateTime? updatedAt,
    String? localId,
    String? firebaseId,
  }) {
    return Crop(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      plantedDate: plantedDate ?? this.plantedDate,
      harvestedDate: harvestedDate ?? this.harvestedDate,
      soldAmount: soldAmount ?? this.soldAmount,
      consumedEstimatedAmount:
          consumedEstimatedAmount ?? this.consumedEstimatedAmount,
      createdAt: createdAt,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      localId: localId ?? this.localId,
      firebaseId: firebaseId ?? this.firebaseId,
    );
  }
}
