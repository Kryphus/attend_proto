import 'package:drift/drift.dart';
import 'db.dart';

class SyncCursorRepo {
  final AppDatabase _db;

  SyncCursorRepo(this._db);

  /// Set the last synced timestamp for a key
  Future<void> setLastSynced(String key, DateTime timestamp) async {
    await _db.into(_db.syncCursor).insertOnConflictUpdate(
      SyncCursorCompanion(
        key: Value(key),
        lastSyncedAt: Value(timestamp),
      ),
    );
  }

  /// Get the last synced timestamp for a key
  Future<DateTime?> getLastSynced(String key) async {
    final query = _db.select(_db.syncCursor)..where((tbl) => tbl.key.equals(key));
    final results = await query.get();
    return results.isNotEmpty ? results.first.lastSyncedAt : null;
  }

  /// Get all sync cursors
  Future<List<SyncCursorData>> getAllCursors() async {
    return await _db.select(_db.syncCursor).get();
  }

  /// Delete a sync cursor
  Future<void> deleteCursor(String key) async {
    await (_db.delete(_db.syncCursor)..where((tbl) => tbl.key.equals(key))).go();
  }

  /// Clear all sync cursors
  Future<void> clearAll() async {
    await _db.delete(_db.syncCursor).go();
  }
}
