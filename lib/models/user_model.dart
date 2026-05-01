/// Local user model stored in encrypted Hive box.
///
/// Passwords are hashed with SHA-256 + per-user random salt.
/// The firebaseUid links this local account to Firebase Auth.
class LocalUser {
  final String id; // UUID generated locally
  final String email;
  final String passwordHash; // SHA-256(password + salt)
  final String salt; // Random per-user salt
  final String? firebaseUid; // Linked Firebase UID
  final DateTime createdAt;

  LocalUser({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.salt,
    this.firebaseUid,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Deserialize from Hive map.
  factory LocalUser.fromMap(Map<String, dynamic> map) {
    return LocalUser(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      passwordHash: map['passwordHash'] ?? '',
      salt: map['salt'] ?? '',
      firebaseUid: map['firebaseUid'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  /// Serialize for Hive storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'passwordHash': passwordHash,
      'salt': salt,
      'firebaseUid': firebaseUid,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  LocalUser copyWith({
    String? id,
    String? email,
    String? passwordHash,
    String? salt,
    String? firebaseUid,
  }) {
    return LocalUser(
      id: id ?? this.id,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      salt: salt ?? this.salt,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      createdAt: createdAt,
    );
  }
}
