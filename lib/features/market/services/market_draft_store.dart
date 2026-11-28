import 'dart:convert';

import '../../../core/services/hive_service.dart';

enum MarketDraftType { profile, listing }

/// Unpublished edits stay local and are identified by their Firebase account.
class MarketDraftStore {
  const MarketDraftStore(this.firebaseUid);

  final String firebaseUid;

  Map<String, dynamic>? read(MarketDraftType type, String draftId) {
    final draft = HiveService.marketDraftsBox.get(_key(type, draftId));
    return draft == null ? null : Map<String, dynamic>.from(draft);
  }

  Future<void> save(
    MarketDraftType type,
    String draftId,
    Map<String, dynamic> fields,
  ) => HiveService.marketDraftsBox.put(_key(type, draftId), fields);

  Future<void> delete(MarketDraftType type, String draftId) =>
      HiveService.marketDraftsBox.delete(_key(type, draftId));

  String _key(MarketDraftType type, String draftId) {
    if (firebaseUid.isEmpty || draftId.isEmpty) {
      throw ArgumentError('A Firebase UID and draft ID are required.');
    }
    return jsonEncode([firebaseUid, type.name, draftId]);
  }
}
