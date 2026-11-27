import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'farm_reset_service.dart';
import 'hive_service.dart';
import 'history_clear_service.dart';
import 'sync_service.dart';

/// Watches the signed-in account's existing collections while sync is enabled.
class LiveFarmSync {
  final SyncService _sync = SyncService();
  final _collections = <StreamSubscription<Object?>>[];
  final _expenses = <String, StreamSubscription<Object?>>{};
  StreamSubscription<Object?>? _settings;
  StreamSubscription<Object?>? _historyClear;
  StreamSubscription<User?>? _auth;
  Timer? _refresh;
  String? _localId;
  String? _firebaseUid;

  void bind(String? localId, String? firebaseUid) {
    if (_localId == localId && _firebaseUid == firebaseUid) return;
    dispose();
    if (localId == null || firebaseUid == null) return;
    _localId = localId;
    _firebaseUid = firebaseUid;
    _settings = HiveService.settingsBox.watch(key: 'isSyncEnabled').listen((_) {
      _updateSubscriptions();
    });
    _historyClear = HiveService.settingsBox
        .watch(key: HistoryClearService.pendingKey(localId))
        .listen((event) {
          if (!event.deleted) _scheduleSync(localId);
        });
    _auth = FirebaseAuth.instance.authStateChanges().listen((_) {
      _updateSubscriptions();
    });
    _updateSubscriptions();
  }

  void _updateSubscriptions() {
    final localId = _localId;
    final uid = _firebaseUid;
    if (localId == null ||
        uid == null ||
        !SyncService.isEnabled ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      _stopWatching();
      return;
    }
    if (_collections.isNotEmpty) return;

    final account = FirebaseFirestore.instance.collection('users').doc(uid);
    final archive = HistoryClearService.marker(account);
    for (final marker in [archive, FarmResetService.marker(account)]) {
      _collections.add(
        marker.snapshots(includeMetadataChanges: true).listen(
          (snapshot) {
            if (!snapshot.metadata.isFromCache &&
                !snapshot.metadata.hasPendingWrites) {
              _scheduleSync(localId);
            }
          },
          onError: (Object error) =>
              debugPrint('Could not watch ${marker.path}: $error'),
        ),
      );
    }
    _watchCropExpenses(account.collection('crops'), 'expenses', localId);
    _watchCropExpenses(
      archive.collection('crops_history'),
      'expenses_history',
      localId,
    );
    _collections.add(_watch(account.collection('common_expenses'), localId));
    _collections.add(_watch(account.collection('crop_history'), localId));
    _collections.add(
      _watch(archive.collection('common_expenses_history'), localId),
    );
  }

  void _watchCropExpenses(
    CollectionReference<Map<String, dynamic>> crops,
    String expenseCollection,
    String localId,
  ) {
    _collections.add(
      _watch(
        crops,
        localId,
        onServerSnapshot: (snapshot) {
          final paths = snapshot.docs
              .map((doc) => doc.reference.collection(expenseCollection).path)
              .toSet();
          for (final id
              in _expenses.keys
                  .where(
                    (path) =>
                        path.startsWith('${crops.path}/') &&
                        !paths.contains(path),
                  )
                  .toList()) {
            unawaited(_expenses.remove(id)?.cancel());
          }
          for (final doc in snapshot.docs) {
            final expenses = doc.reference.collection(expenseCollection);
            _expenses.putIfAbsent(
              expenses.path,
              () => _watch(expenses, localId),
            );
          }
        },
      ),
    );
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _watch(
    CollectionReference<Map<String, dynamic>> collection,
    String localId, {
    void Function(QuerySnapshot<Map<String, dynamic>>)? onServerSnapshot,
  }) {
    // Also act on reconnect even if the cached document contents stayed the same.
    var needsServerSnapshot = true;
    return collection
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (snapshot.metadata.isFromCache ||
                snapshot.metadata.hasPendingWrites) {
              needsServerSnapshot = true;
              return;
            }
            if (_localId != localId || !_isCurrentSession) return;
            onServerSnapshot?.call(snapshot);
            if (needsServerSnapshot || snapshot.docChanges.isNotEmpty) {
              needsServerSnapshot = false;
              _scheduleSync(localId);
            }
          },
          onError: (Object error) {
            debugPrint('Could not watch ${collection.path}: $error');
          },
        );
  }

  void _scheduleSync(
    String localId, {
    Duration delay = const Duration(milliseconds: 350),
  }) {
    if (_localId != localId || !_isCurrentSession) return;
    _refresh ??= Timer(delay, () async {
      _refresh = null;
      if (_localId != localId || !_isCurrentSession) return;
      try {
        await _sync.immediateSync(localId);
      } catch (error) {
        debugPrint('Live farm sync failed: $error');
      }
      if (HistoryClearService.pending(localId) != null) {
        _scheduleSync(localId, delay: const Duration(seconds: 15));
      }
    });
  }

  bool get _isCurrentSession =>
      SyncService.isEnabled &&
      _firebaseUid != null &&
      FirebaseAuth.instance.currentUser?.uid == _firebaseUid;

  void _stopWatching() {
    _refresh?.cancel();
    _refresh = null;
    for (final subscription in [..._collections, ..._expenses.values]) {
      unawaited(subscription.cancel());
    }
    _collections.clear();
    _expenses.clear();
  }

  void dispose() {
    _stopWatching();
    unawaited(_settings?.cancel());
    unawaited(_historyClear?.cancel());
    unawaited(_auth?.cancel());
    _settings = null;
    _historyClear = null;
    _auth = null;
    _localId = null;
    _firebaseUid = null;
  }
}
