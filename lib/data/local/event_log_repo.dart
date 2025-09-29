import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'db.dart';
import '../../services/logging_service.dart';

enum EventType {
  attendIn('ATTEND_IN'),
  attendOut('ATTEND_OUT'),
  heartbeat('HEARTBEAT');

  const EventType(this.value);
  final String value;

  static EventType fromString(String value) {
    return EventType.values.firstWhere((e) => e.value == value);
  }
}

enum EventStatus {
  pending('PENDING'),
  confirmed('CONFIRMED'),
  rejected('REJECTED');

  const EventStatus(this.value);
  final String value;

  static EventStatus fromString(String value) {
    return EventStatus.values.firstWhere((e) => e.value == value);
  }
}

class EventLogRepo {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  EventLogRepo(this._db);

  /// Append a new event to the log with PENDING status
  Future<String> append(EventType type, Map<String, dynamic> payload) async {
    final eventId = _uuid.v4();
    
    await _db.into(_db.eventLog).insert(
      EventLogCompanion(
        id: Value(eventId),
        type: Value(type.value),
        payload: Value(_encodePayload(payload)),
        createdAt: Value(DateTime.now()),
        status: Value(EventStatus.pending.value),
      ),
    );

    logger.info(
      'Event appended',
      'EventLogRepo',
      {
        'event_id': eventId,
        'type': type.value,
        'status': EventStatus.pending.value,
        'payload_keys': payload.keys.toList(),
      },
    );

    return eventId;
  }

  /// Mark an event's status and optionally set server reason
  Future<void> markStatus(String id, EventStatus status, [String? serverReason]) async {
    await (_db.update(_db.eventLog)..where((tbl) => tbl.id.equals(id))).write(
      EventLogCompanion(
        status: Value(status.value),
        serverReason: Value(serverReason),
      ),
    );

    logger.info(
      'Event status updated',
      'EventLogRepo',
      {
        'event_id': id,
        'new_status': status.value,
        'server_reason': serverReason,
      },
    );
  }

  /// Get all events, optionally filtered by status
  Future<List<EventLogData>> getEvents({EventStatus? status, int? limit}) async {
    final query = _db.select(_db.eventLog)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    
    if (status != null) {
      query.where((tbl) => tbl.status.equals(status.value));
    }
    
    if (limit != null) {
      query.limit(limit);
    }
    
    return await query.get();
  }

  /// Get event by ID
  Future<EventLogData?> getEventById(String id) async {
    final query = _db.select(_db.eventLog)..where((tbl) => tbl.id.equals(id));
    final results = await query.get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Get count of events by status
  Future<int> getCountByStatus(EventStatus status) async {
    final query = _db.selectOnly(_db.eventLog)
      ..addColumns([_db.eventLog.id.count()])
      ..where(_db.eventLog.status.equals(status.value));
    
    final result = await query.getSingle();
    return result.read(_db.eventLog.id.count()) ?? 0;
  }

  /// Delete events older than specified duration
  Future<int> deleteOldEvents(Duration maxAge) async {
    final cutoffTime = DateTime.now().subtract(maxAge);
    return await (_db.delete(_db.eventLog)
      ..where((tbl) => tbl.createdAt.isSmallerThanValue(cutoffTime))).go();
  }

  String _encodePayload(Map<String, dynamic> payload) {
    // For now, use toString() - in production you'd use dart:convert jsonEncode
    return payload.toString();
  }
}
