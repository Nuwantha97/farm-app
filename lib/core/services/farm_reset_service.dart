import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'history_clear_service.dart';
import 'hive_service.dart';

class FarmResetService {
  static const _server = GetOptions(source: Source.server);
  static const _timeout = Duration(seconds: 20);
  static const _batchSize = 8;
  static const _uuid = Uuid();
  static final _busy = <String>{};
  static String requestKey(String userId) => 'farmResetRequest/$userId';
  static String _generationKey(String userId) => 'farmGeneration/$userId';
  static String _runningKey(String userId) => 'farmResetRunning/$userId';

  static DocumentReference<Map<String, dynamic>> marker(
    DocumentReference<Map<String, dynamic>> account,
  ) => account.collection('operations').doc('farm_reset');

  static bool isBlocked(String userId) =>
      _busy.contains(userId) ||
      HiveService.settingsBox.get(_runningKey(userId)) == true;

  static bool needsRetry(String userId) =>
      HiveService.settingsBox.containsKey(requestKey(userId)) ||
      HiveService.settingsBox.get(_runningKey(userId)) == true;

  static void requireWritable(String userId) {
    if (isBlocked(userId)) throw StateError('A farm reset is in progress.');
  }

  static bool pause(String userId) => _busy.add(userId);
  static void resume(String userId) => _busy.remove(userId);

  static Future<Map<String, dynamic>?> _read(
    DocumentReference<Map<String, dynamic>> account,
  ) async => (await marker(account).get(_server).timeout(_timeout)).data();

  /// Check the generation before uploading any local records, including queued edits.
  static Future<String?> prepareSync(
    String userId,
    DocumentReference<Map<String, dynamic>> account,
  ) async {
    Map<String, dynamic>? state;
    try {
      state = await _read(account);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' &&
          !HiveService.settingsBox.containsKey(_generationKey(userId)) &&
          !needsRetry(userId)) {
        return null;
      }
      rethrow;
    }
    if (state == null) return null;
    if (state['status'] == 'running') {
      await HiveService.settingsBox.put(_runningKey(userId), true);
      throw StateError(
        'A farm reset is in progress. Open Settings to retry if interrupted.',
      );
    }
    final generation = state['generation'] as String;
    await _apply(userId, generation);
    return generation;
  }

  /// Keep the reset marker running until all farm collections are empty.
  static Future<void> reset(
    String userId,
    DocumentReference<Map<String, dynamic>> account,
  ) async {
    final settings = HiveService.settingsBox;
    final state = await _read(account);
    final generation = state?['generation'] as String?;
    final pending = settings.get(requestKey(userId)) as Map?;
    if (generation != null &&
        state?['status'] == 'complete' &&
        pending != null &&
        (pending['requestId'] == generation ||
            pending['baseGeneration'] != generation)) {
      await _apply(userId, generation);
      return;
    }

    final requestId = pending?['requestId'] as String? ?? _uuid.v4();
    await settings.put(requestKey(userId), {
      'requestId': requestId,
      'baseGeneration': generation,
    });

    final resetRef = marker(account);
    final running = await account.firestore.runTransaction((transaction) async {
      _requireSession(account);
      final latest = (await transaction.get(resetRef)).data();
      if (latest?['status'] == 'running') {
        final lease = latest?['leaseUntil'] as Timestamp?;
        if (lease != null && lease.toDate().isAfter(DateTime.now())) {
          throw StateError('A reset is already running. Try again shortly.');
        }
        return _runningState(
          latest!['generation'] as String,
          latest['baseGeneration'] as String?,
        );
      }
      if (latest?['status'] == 'complete' &&
          (state?['status'] == 'running' ||
              latest?['generation'] == requestId)) {
        return latest!;
      }
      if (latest?['generation'] != generation) {
        throw StateError('The farm reset status changed. Sync and try again.');
      }
      final running = _runningState(requestId, generation);
      transaction.set(resetRef, running);
      return running;
    }, timeout: _timeout);
    final resetGeneration = running['generation'] as String;
    if (running['status'] == 'complete') {
      await _apply(userId, resetGeneration);
      return;
    }
    await settings.put(requestKey(userId), {
      'requestId': resetGeneration,
      'baseGeneration': running['baseGeneration'],
    });
    await settings.put(_runningKey(userId), true);

    try {
      await _deleteFarm(account, running);
      await account.firestore.runTransaction((transaction) async {
        _requireSession(account);
        final latest = (await transaction.get(resetRef)).data();
        if (latest?['generation'] != resetGeneration) {
          throw StateError(
            'The farm reset status changed. Sync and try again.',
          );
        }
        if (latest?['status'] == 'running') {
          transaction.set(resetRef, {
            'generation': resetGeneration,
            'status': 'complete',
          });
        }
      }, timeout: _timeout);
    } catch (_) {
      // Another device may have finished this request between batches.
      final latest = await _read(account);
      if (latest?['generation'] != resetGeneration ||
          latest?['status'] != 'complete') {
        rethrow;
      }
    }
    await _apply(userId, resetGeneration);
  }

  static Map<String, dynamic> _runningState(
    String generation,
    String? baseGeneration,
  ) => {
    'generation': generation,
    'baseGeneration': baseGeneration,
    'status': 'running',
    'batchToken': _uuid.v4(),
  };

  static User _requireSession(DocumentReference<Map<String, dynamic>> account) {
    final user = FirebaseAuth.instanceFor(app: account.firestore.app)
        .currentUser;
    if (user?.uid != account.id ||
        HiveService.settingsBox.get('isSyncEnabled', defaultValue: false) !=
            true) {
      throw StateError('Sign in with cloud sync enabled to finish the reset.');
    }
    return user!;
  }

  static Future<void> _deleteFarm(
    DocumentReference<Map<String, dynamic>> account,
    Map<String, dynamic> running,
  ) async {
    final archive = HistoryClearService.marker(account);
    await _deleteNestedExpenses(account, account, 'crops', 'expenses', running);
    await _deleteNestedExpenses(
      account,
      archive,
      'crops_history',
      'expenses_history',
      running,
    );
    for (final collection in [
      account.collection('crops'),
      account.collection('common_expenses'),
      account.collection('crop_history'),
      account.collection('sales'),
      archive.collection('crops_history'),
      archive.collection('common_expenses_history'),
    ]) {
      await _deleteCollection(account, collection, running);
    }
    _requireSession(account);
    if ((await archive.get(_server).timeout(_timeout)).exists) {
      await _deleteBatch(account, [archive], running);
    }
  }

  static Future<void> _deleteNestedExpenses(
    DocumentReference<Map<String, dynamic>> account,
    DocumentReference<Map<String, dynamic>> parent,
    String crops,
    String expenses,
    Map<String, dynamic> running,
  ) async {
    // A scoped collection-group query finds expenses even under missing crops.
    final client = http.Client();
    try {
      while (true) {
        final docs = await _queryExpenses(
          client,
          account,
          parent,
          crops,
          expenses,
        );
        if (docs.isEmpty) return;
        await _deleteBatch(account, docs, running);
      }
    } finally {
      client.close();
    }
  }

  static Future<List<DocumentReference<Map<String, dynamic>>>> _queryExpenses(
    http.Client client,
    DocumentReference<Map<String, dynamic>> account,
    DocumentReference<Map<String, dynamic>> parent,
    String crops,
    String expenses,
  ) async {
    final user = _requireSession(account);
    final db = account.firestore;
    final settings = db.settings;
    final origin = Uri.parse(
      '${settings.sslEnabled == false ? 'http' : 'https'}://${settings.host ?? 'firestore.googleapis.com'}',
    );
    final root = [
      'projects',
      db.app.options.projectId,
      'databases',
      db.databaseId,
      'documents',
    ];
    final parentPath = parent.path.split('/');
    final uri = origin.replace(
      pathSegments: [
        'v1',
        ...root,
        ...parentPath.take(parentPath.length - 1),
        '${parent.id}:runQuery',
      ],
    );
    final prefix = '${[...root, ...parentPath].join('/')}/$crops/';
    final token = await user.getIdToken().timeout(_timeout);
    if (token == null) throw StateError('Sign in again to finish the reset.');
    _requireSession(account);
    final result = await client
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'structuredQuery': {
              'select': {
                'fields': [
                  {'fieldPath': '__name__'},
                ],
              },
              'from': [
                {'collectionId': expenses, 'allDescendants': true},
              ],
              'limit': _batchSize,
            },
          }),
        )
        .timeout(_timeout);
    if (result.statusCode != 200) {
      throw StateError(
        'Could not read crop expenses from Firestore (${result.statusCode}). Try the reset again.',
      );
    }
    final docs = <DocumentReference<Map<String, dynamic>>>[];
    for (final row in jsonDecode(result.body) as List) {
      if (row['error'] != null) {
        throw StateError(
          'Firestore did not finish reading crop expenses. Try the reset again.',
        );
      }
      final name = row['document']?['name'] as String?;
      if (name == null) continue;
      final parts = name.startsWith(prefix)
          ? name.substring(prefix.length).split('/')
          : const <String>[];
      if (parts.length != 3 ||
          parts[1] != expenses ||
          parts.first.isEmpty ||
          parts.last.isEmpty) {
        throw StateError('Unexpected Firestore expense path.');
      }
      docs.add(
        parent
            .collection(crops)
            .doc(parts[0])
            .collection(expenses)
            .doc(parts[2]),
      );
    }
    return docs;
  }

  static Future<void> _deleteCollection(
    DocumentReference<Map<String, dynamic>> account,
    CollectionReference<Map<String, dynamic>> collection,
    Map<String, dynamic> running,
  ) async {
    while (true) {
      _requireSession(account);
      final page = await collection
          .limit(_batchSize)
          .get(_server)
          .timeout(_timeout);
      if (page.docs.isEmpty) return;
      await _deleteBatch(
        account,
        page.docs.map((doc) => doc.reference),
        running,
      );
    }
  }

  static Future<void> _deleteBatch(
    DocumentReference<Map<String, dynamic>> account,
    Iterable<DocumentReference<Map<String, dynamic>>> docs,
    Map<String, dynamic> running,
  ) async {
    _requireSession(account);
    final batch = account.firestore.batch();
    // The same commit must touch the running marker. Rules reject a batch
    // that arrives after another device finishes or starts a newer reset.
    batch.set(marker(account), {...running, 'batchToken': _uuid.v4()});
    for (final doc in docs) {
      batch.delete(doc);
    }
    await batch.commit().timeout(_timeout);
  }

  static Future<void> _apply(String userId, String generation) async {
    final settings = HiveService.settingsBox;
    if (settings.get(_generationKey(userId)) != generation) {
      final pausedHere = pause(userId);
      try {
        await settings.put(_runningKey(userId), true);
        await HiveService.clearFarmDataForUser(userId);
        await HistoryClearService.forget(userId);
        await settings.put(_generationKey(userId), generation);
      } finally {
        if (pausedHere) resume(userId);
      }
    }
    if (settings.containsKey(_runningKey(userId))) {
      await settings.delete(_runningKey(userId));
    }
    final pending = settings.get(requestKey(userId)) as Map?;
    if (pending != null &&
        (pending['requestId'] == generation ||
            pending['baseGeneration'] != generation)) {
      await settings.delete(requestKey(userId));
    }
  }
}
