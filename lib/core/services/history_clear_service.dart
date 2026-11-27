import 'package:cloud_firestore/cloud_firestore.dart';

import 'hive_service.dart';

/// A durable per-account request and the last observed cloud history cutoff.
class HistoryClearService {
  static String pendingKey(String userId) => 'historyClearPending/$userId';
  static String _cutoffKey(String userId) => 'historyClearedThrough/$userId';

  static Future<void> forget(String userId) => HiveService.settingsBox
      .deleteAll([pendingKey(userId), _cutoffKey(userId)]);

  static DocumentReference<Map<String, dynamic>> marker(
    DocumentReference<Map<String, dynamic>> account,
  ) => account.collection('history').doc('archive');

  static Map? pending(String userId) =>
      HiveService.settingsBox.get(pendingKey(userId)) as Map?;

  static DateTime? cutoff(String userId) {
    final queued = _date(pending(userId)?['cutoff']);
    final synced = _date(HiveService.settingsBox.get(_cutoffKey(userId)));
    return queued != null && (synced == null || queued.isAfter(synced))
        ? queued
        : synced;
  }

  static bool isArchived(Map data) =>
      data['isArchived'] == true || data['archivedAt'] != null;

  static bool isCleared(Map data, DateTime? cutoff) {
    if (cutoff == null) return false;
    final archivedAt = _date(data['archivedAt']);
    // Legacy history without an archive date predates the clear feature.
    return archivedAt == null || !archivedAt.isAfter(cutoff);
  }

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp value => value.toDate(),
    String value => DateTime.tryParse(value),
    _ => null,
  };

  static Future<void> queue(String userId) async {
    final previous = pending(userId);
    if (previous != null) {
      await _clearLocal(userId, _date(previous['cutoff'])!);
      return;
    }

    final now = DateTime.now().toUtc();
    final ids = _localArchivedCropIds(userId, now);
    final cropSources = {...ids};
    final commonSources = <String>{};
    for (final entry in HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    )) {
      if (!ids.contains(entry.key.substring(userId.length + 1))) continue;
      final firebaseId = entry.value['firebaseId'];
      if (firebaseId is String) cropSources.add(firebaseId);
    }
    for (final entry in HiveService.getItemsByUser(
      HiveService.commonExpenseHistoryBox,
      userId,
    )) {
      if (!isCleared(entry.value, now)) continue;
      commonSources.add(entry.key.substring('${userId}_common_'.length));
      final current = HiveService.commonExpensesBox.get(entry.key);
      final firebaseId =
          current?['firebaseId'] ?? entry.value['originalFirebaseId'];
      if (firebaseId is String) commonSources.add(firebaseId);
    }

    await HiveService.settingsBox.put(pendingKey(userId), {
      'cutoff': now.toIso8601String(),
      'cropSources': cropSources.toList(),
      'commonSources': commonSources.toList(),
    });
    await _clearLocal(userId, now);
  }

  static Future<void> resumeLocal(String userId) async {
    final requestedAt = _date(pending(userId)?['cutoff']);
    if (requestedAt != null) await _clearLocal(userId, requestedAt);
  }

  static Set<String> _localArchivedCropIds(String userId, DateTime cutoff) => {
    for (final entry in HiveService.getItemsByUser(
      HiveService.cropHistoryBox,
      userId,
    ))
      if (isCleared(entry.value, cutoff))
        entry.key.substring(userId.length + 1),
    for (final entry in HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    ))
      if (isArchived(entry.value) && isCleared(entry.value, cutoff))
        entry.key.substring(userId.length + 1),
  };

  static Future<void> _clearLocal(String userId, DateTime cutoff) async {
    final ids = _localArchivedCropIds(userId, cutoff);
    final crops = HiveService.cropsBox;
    final aliases = {...ids};
    for (final id in ids) {
      final firebaseId = crops.get('${userId}_$id')?['firebaseId'];
      if (firebaseId is String) aliases.add(firebaseId);
    }
    final expenseKeys = aliases.map((id) => '${userId}_${id}_').toList();
    final expenses = HiveService.expensesBox;
    await expenses.deleteAll(
      HiveService.getItemsByUser(expenses, userId)
          .where(
            (entry) =>
                aliases.contains(entry.value['cropId']) ||
                expenseKeys.any(entry.key.startsWith),
          )
          .map((entry) => entry.key),
    );
    final expenseHistory = HiveService.expenseHistoryBox;
    await expenseHistory.deleteAll(
      HiveService.getItemsByUser(expenseHistory, userId)
          .where((entry) => isCleared(entry.value, cutoff))
          .map((entry) => entry.key),
    );
    await crops.deleteAll(ids.map((id) => '${userId}_$id'));
    await HiveService.cropHistoryBox.deleteAll(
      ids.map((id) => '${userId}_$id'),
    );
    final commonHistory = HiveService.commonExpenseHistoryBox;
    final commonKeys = HiveService.getItemsByUser(commonHistory, userId)
        .where((entry) => isCleared(entry.value, cutoff))
        .map((entry) => entry.key)
        .toList();
    await HiveService.commonExpensesBox.deleteAll(commonKeys);
    await commonHistory.deleteAll(commonKeys);
  }

  /// Called before the normal push/pull so another device cannot restore old Hive rows.
  static Future<void> synchronize(
    String userId,
    DocumentReference<Map<String, dynamic>> account,
    bool Function() canSync, {
    String? farmGeneration,
  }) async {
    final markerRef = marker(account);
    final request = pending(userId);
    final requestedAt = _date(request?['cutoff']);
    DateTime? cloudCutoff;
    if (requestedAt == null) {
      try {
        cloudCutoff = _date(
          (await markerRef.get(const GetOptions(source: Source.server)))
              .data()?['clearedThrough'],
        );
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' && cutoff(userId) == null) return;
        rethrow;
      }
    } else {
      cloudCutoff = await account.firestore.runTransaction((transaction) async {
        final previous = _date(
          (await transaction.get(markerRef)).data()?['clearedThrough'],
        );
        if (previous != null && !requestedAt.isAfter(previous)) return previous;
        if (!canSync()) return previous;
        transaction.set(markerRef, {
          'clearedThrough': Timestamp.fromDate(requestedAt),
          'farmGeneration': ?farmGeneration,
        });
        return requestedAt;
      });
    }
    if (!canSync() || cloudCutoff == null) return;
    final savedCutoff = cloudCutoff.toUtc().toIso8601String();
    if (request != null ||
        HiveService.settingsBox.get(_cutoffKey(userId)) != savedCutoff) {
      await _clearLocal(userId, cloudCutoff);
      await HiveService.settingsBox.put(_cutoffKey(userId), savedCutoff);
    }
    if (request == null || !canSync()) return;

    await _clearCloud(account, cloudCutoff, request, canSync);
    if (canSync() && pending(userId)?['cutoff'] == request['cutoff']) {
      await HiveService.settingsBox.delete(pendingKey(userId));
    }
  }

  static Future<void> _clearCloud(
    DocumentReference<Map<String, dynamic>> account,
    DateTime cutoff,
    Map request,
    bool Function() canSync,
  ) async {
    const server = GetOptions(source: Source.server);
    final archive = marker(account);
    final archivedCrops = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...(await account.collection('crop_history').get(server)).docs,
      ...(await archive.collection('crops_history').get(server)).docs,
    ].where((doc) => isCleared(doc.data(), cutoff)).toList();
    final cropSources = {
      ...List<String>.from(request['cropSources'] as List),
      for (final doc in archivedCrops)
        (doc.data()['localId'] as String? ?? doc.id),
    };
    for (final doc in (await account.collection('crops').get(server)).docs) {
      final data = doc.data();
      if ((isArchived(data) && isCleared(data, cutoff)) ||
          (!isArchived(data) &&
              (cropSources.contains(doc.id) ||
                  cropSources.contains(data['localId'])))) {
        await _deleteTree(doc.reference, 'expenses', canSync);
      }
    }
    for (final doc in archivedCrops) {
      _requireSync(canSync);
      if (doc.reference.parent.id == 'crops_history') {
        await _deleteTree(doc.reference, 'expenses_history', canSync);
      } else {
        await doc.reference.delete();
      }
    }

    final common =
        (await archive.collection('common_expenses_history').get(server)).docs
            .where((doc) => isCleared(doc.data(), cutoff))
            .toList();
    final commonSources = {
      ...List<String>.from(request['commonSources'] as List),
      for (final doc in common) (doc.data()['localId'] as String? ?? doc.id),
      for (final doc in common)
        if (doc.data()['originalFirebaseId'] is String)
          doc.data()['originalFirebaseId'],
    };
    final active = (await account.collection('common_expenses').get(server))
        .docs
        .where(
          (doc) =>
              commonSources.contains(doc.id) ||
              commonSources.contains(doc.data()['localId']),
        );
    await _deleteDocuments(account.firestore, [...active, ...common], canSync);
  }

  static Future<void> _deleteTree(
    DocumentReference<Map<String, dynamic>> parent,
    String children,
    bool Function() canSync,
  ) async {
    _requireSync(canSync);
    final docs =
        (await parent
                .collection(children)
                .get(const GetOptions(source: Source.server)))
            .docs;
    await _deleteDocuments(parent.firestore, docs, canSync);
    _requireSync(canSync);
    await parent.delete();
  }

  static Future<void> _deleteDocuments(
    FirebaseFirestore db,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool Function() canSync,
  ) async {
    // Reset rules can read two marker snapshots per write.
    for (var start = 0; start < docs.length; start += 10) {
      _requireSync(canSync);
      final batch = db.batch();
      for (final doc in docs.skip(start).take(10)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  static void _requireSync(bool Function() canSync) {
    if (!canSync()) throw StateError('History deletion interrupted');
  }
}
