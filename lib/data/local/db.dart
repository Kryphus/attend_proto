import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:sqlite3/sqlite3.dart';

part 'db.g.dart';

// Event Log Table
class EventLog extends Table {
  TextColumn get id => text()();
  TextColumn get type => text().withLength(min: 1, max: 20)();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text().withLength(min: 1, max: 20)();
  TextColumn get serverReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Outbox Table
class Outbox extends Table {
  TextColumn get id => text()();
  TextColumn get eventId => text()();
  TextColumn get dedupeKey => text().unique()();
  TextColumn get endpoint => text()();
  TextColumn get method => text()();
  TextColumn get payload => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Sync Cursor Table
class SyncCursor extends Table {
  TextColumn get key => text()();
  DateTimeColumn get lastSyncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [EventLog, Outbox, SyncCursor])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.withExecutor(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Handle future migrations here
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attend_proto.db'));

    // Make sqlite3 available on Android and iOS
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    // Make the sqlite3 library available on Linux as well
    if (Platform.isLinux) {
      sqlite3.tempDirectory = (await getTemporaryDirectory()).path;
    }

    return NativeDatabase.createInBackground(file);
  });
}
