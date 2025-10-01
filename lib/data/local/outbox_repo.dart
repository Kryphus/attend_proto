import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:sqlite3/sqlite3.dart';
import 'dart:convert';
import 'db.dart';
import '../../services/logging_service.dart';

class OutboxItem {
  final String id;
  final String eventId;
  final String dedupeKey;
  final String endpoint;
  final String method;
  final Map<String, dynamic> payload;
  final int attempts;
  final DateTime nextAttemptAt;
  final String? lastError;

  OutboxItem({
    required this.id,
    required this.eventId,
    required this.dedupeKey,
    required this.endpoint,
    required this.method,
    required this.payload,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
  });

  factory OutboxItem.fromData(OutboxData data) {
    return OutboxItem(
      id: data.id,
      eventId: data.eventId,
      dedupeKey: data.dedupeKey,
      endpoint: data.endpoint,
      method: data.method,
      payload: _decodePayload(data.payload),
      attempts: data.attempts,
      nextAttemptAt: data.nextAttemptAt,
      lastError: data.lastError,
    );
  }

  static Map<String, dynamic> _decodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {};
    } catch (_) {
      return {};
    }
  }
}

class OutboxRepo {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  OutboxRepo(this._db);

  /// Enqueue an event for sync
  Future<String> enqueue({
    required String eventId,
    required String dedupeKey,
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) async {
    final outboxId = _uuid.v4();
    
    try {
      await _db.into(_db.outbox).insert(
        OutboxCompanion(
          id: Value(outboxId),
          eventId: Value(eventId),
          dedupeKey: Value(dedupeKey),
          endpoint: Value(endpoint),
          method: Value(method),
          payload: Value(_encodePayload(payload)),
          attempts: const Value(0),
          nextAttemptAt: Value(DateTime.now()),
        ),
      );

      logger.info(
        'Outbox item enqueued',
        'OutboxRepo',
        {
          'outbox_id': outboxId,
          'event_id': eventId,
          'dedupe_key': dedupeKey,
          'endpoint': endpoint,
          'method': method,
        },
      );

      return outboxId;
    } on SqliteException catch (e) {
      // Handle unique constraint violation for dedupe_key
      if (e.message.contains('UNIQUE constraint failed')) {
        throw DuplicateDedupeKeyException(dedupeKey);
      }
      rethrow;
    } catch (e) {
      // Handle other database exceptions
      if (e.toString().contains('UNIQUE constraint failed')) {
        throw DuplicateDedupeKeyException(dedupeKey);
      }
      rethrow;
    }
  }

  /// Get a batch of items ready for sync
  Future<List<OutboxItem>> dequeueBatch({int limit = 10}) async {
    final query = _db.select(_db.outbox)
      ..where((tbl) => tbl.nextAttemptAt.isSmallerOrEqualValue(DateTime.now()))
      ..orderBy([(t) => OrderingTerm.asc(t.nextAttemptAt)])
      ..limit(limit);
    
    final results = await query.get();
    return results.map((data) => OutboxItem.fromData(data)).toList();
  }

  /// Mark an attempt and optionally set error
  Future<void> markAttempt(String id, {String? error}) async {
    // First get current attempts count
    final query = _db.select(_db.outbox)..where((tbl) => tbl.id.equals(id));
    final results = await query.get();
    if (results.isNotEmpty) {
      final currentAttempts = results.first.attempts;
      await (_db.update(_db.outbox)..where((tbl) => tbl.id.equals(id))).write(
        OutboxCompanion(
          attempts: Value(currentAttempts + 1),
          lastError: Value(error),
        ),
      );
    }
  }

  /// Schedule next attempt with backoff
  Future<void> scheduleNextAttempt(String id, DateTime nextAttemptAt) async {
    await (_db.update(_db.outbox)..where((tbl) => tbl.id.equals(id))).write(
      OutboxCompanion(
        nextAttemptAt: Value(nextAttemptAt),
      ),
    );
  }

  /// Remove successfully synced item
  Future<void> removeItem(String id) async {
    await (_db.delete(_db.outbox)..where((tbl) => tbl.id.equals(id))).go();
  }

  /// Get count of pending items
  Future<int> getPendingCount() async {
    final query = _db.selectOnly(_db.outbox)
      ..addColumns([_db.outbox.id.count()]);
    
    final result = await query.getSingle();
    return result.read(_db.outbox.id.count()) ?? 0;
  }

  /// Get all items for debugging
  Future<List<OutboxItem>> getAllItems() async {
    final query = _db.select(_db.outbox)..orderBy([(t) => OrderingTerm.desc(t.nextAttemptAt)]);
    final results = await query.get();
    return results.map((data) => OutboxItem.fromData(data)).toList();
  }

  /// Get items by event ID
  Future<List<OutboxItem>> getItemsByEventId(String eventId) async {
    final query = _db.select(_db.outbox)..where((tbl) => tbl.eventId.equals(eventId));
    final results = await query.get();
    return results.map((data) => OutboxItem.fromData(data)).toList();
  }

  /// Delete items older than specified duration
  Future<int> deleteOldItems(Duration maxAge) async {
    final cutoffTime = DateTime.now().subtract(maxAge);
    return await (_db.delete(_db.outbox)
      ..where((tbl) => tbl.nextAttemptAt.isSmallerThanValue(cutoffTime))).go();
  }

  String _encodePayload(Map<String, dynamic> payload) {
    try {
      return jsonEncode(payload);
    } catch (_) {
      return '{}';
    }
  }
}

class DuplicateDedupeKeyException implements Exception {
  final String dedupeKey;
  
  DuplicateDedupeKeyException(this.dedupeKey);
  
  @override
  String toString() => 'Duplicate dedupe key: $dedupeKey';
}
