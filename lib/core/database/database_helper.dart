import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cryptoview.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (!kIsWeb && Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final directory = await getApplicationSupportDirectory();
      path = join(directory.path, 'CryptoView', filePath);
      
      // Ensure the directory exists
      final fileDir = Directory(join(directory.path, 'CryptoView'));
      if (!await fileDir.exists()) {
        await fileDir.create(recursive: true);
      }
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }

    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. Table for Transactions (Diario de trading)
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exchange TEXT NOT NULL,
        symbol TEXT NOT NULL,
        type TEXT NOT NULL, -- 'buy' or 'sell'
        price REAL NOT NULL,
        amount REAL NOT NULL,
        fee REAL NOT NULL,
        date TEXT NOT NULL,
        is_matched INTEGER DEFAULT 0 -- 0 = false, 1 = true (fully matched)
      )
    ''');

    // 2. Table for Matches (Casamientos de operaciones)
    await db.execute('''
      CREATE TABLE matches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        buy_transaction_id INTEGER NOT NULL,
        sell_transaction_id INTEGER DEFAULT 0,
        matched_amount REAL NOT NULL,
        profit REAL NOT NULL,
        date TEXT NOT NULL,
        withdrawal_id INTEGER DEFAULT NULL,
        match_type TEXT DEFAULT 'trade', -- 'trade' or 'expense'
        notes TEXT DEFAULT '',
        FOREIGN KEY (buy_transaction_id) REFERENCES transactions (id) ON DELETE CASCADE
      )
    ''');

    // 3. Table for Chart drawings (Líneas horizontales)
    await db.execute('''
      CREATE TABLE drawings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exchange TEXT NOT NULL,
        symbol TEXT NOT NULL,
        price REAL NOT NULL,
        color TEXT NOT NULL,
        label TEXT NOT NULL
      )
    ''');

    // 4. Table for API keys (Read-Only)
    await db.execute('''
      CREATE TABLE api_keys (
        exchange TEXT PRIMARY KEY,
        api_key TEXT NOT NULL,
        api_secret TEXT NOT NULL,
        api_passphrase TEXT DEFAULT ""
      )
    ''');

    // 5. Table for API Sync logs
    await db.execute('''
      CREATE TABLE api_sync (
        exchange TEXT NOT NULL,
        symbol TEXT NOT NULL,
        last_sync_date TEXT NOT NULL,
        PRIMARY KEY (exchange, symbol)
      )
    ''');

    // 6. Table for Favorites
    await db.execute('''
      CREATE TABLE favorites (
        symbol TEXT PRIMARY KEY
      )
    ''');

    // 7. Table for Exchange Settings (e.g. default buy amounts)
    await db.execute('''
      CREATE TABLE exchange_settings (
        exchange TEXT PRIMARY KEY,
        default_buy_amount REAL DEFAULT 100.0
      )
    ''');

    // 8. Table for General App Settings (Key-Value)
    await db.execute('''
      CREATE TABLE general_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 9. Table for Withdrawals / Expenses (Salidas y Gastos de Consumo)
    await db.execute('''
      CREATE TABLE withdrawals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exchange TEXT NOT NULL,
        currency TEXT NOT NULL,
        amount REAL NOT NULL,
        fee REAL NOT NULL DEFAULT 0.0,
        date TEXT NOT NULL,
        tx_id TEXT,
        address TEXT,
        description TEXT,
        category TEXT DEFAULT 'Gasto Personal',
        is_matched INTEGER DEFAULT 0
      )
    ''');

    // 10. Table for Candlesticks (Velas historicas de mercado)
    await db.execute('''
      CREATE TABLE candles (
        exchange TEXT NOT NULL,
        symbol TEXT NOT NULL,
        interval TEXT NOT NULL,
        time INTEGER NOT NULL,
        open REAL NOT NULL,
        high REAL NOT NULL,
        low REAL NOT NULL,
        close REAL NOT NULL,
        volume REAL DEFAULT 0.0,
        PRIMARY KEY (exchange, symbol, interval, time)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_candles_lookup ON candles(exchange, symbol, interval, time)');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE api_keys ADD COLUMN api_passphrase TEXT DEFAULT ""');
      } catch (e) {
        print("Error altering api_keys: \$e");
      }
      try {
        await db.execute('''
          CREATE TABLE api_sync (
            exchange TEXT NOT NULL,
            symbol TEXT NOT NULL,
            last_sync_date TEXT NOT NULL,
            PRIMARY KEY (exchange, symbol)
          )
        ''');
      } catch (e) {
        print("Error creating api_sync: \$e");
      }
    }
    if (oldVersion < 3) {
      try {
        await db.execute('CREATE TABLE IF NOT EXISTS favorites (symbol TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE IF NOT EXISTS exchange_settings (exchange TEXT PRIMARY KEY, default_buy_amount REAL DEFAULT 100.0)');
      } catch (e) {
        print("Error upgrading DB to v3: \$e");
      }
    }
    if (oldVersion < 4) {
      try {
        await db.execute('CREATE TABLE IF NOT EXISTS general_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      } catch (e) {
        print("Error upgrading DB to v4: \$e");
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS withdrawals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exchange TEXT NOT NULL,
            currency TEXT NOT NULL,
            amount REAL NOT NULL,
            fee REAL NOT NULL DEFAULT 0.0,
            date TEXT NOT NULL,
            tx_id TEXT,
            address TEXT,
            description TEXT,
            category TEXT DEFAULT 'Gasto Personal',
            is_matched INTEGER DEFAULT 0
          )
        ''');
      } catch (e) {
        print("Error creating withdrawals table: \$e");
      }
      try {
        await db.execute('ALTER TABLE matches ADD COLUMN withdrawal_id INTEGER DEFAULT NULL');
      } catch (e) {
        print("Error adding withdrawal_id to matches: \$e");
      }
      try {
        await db.execute("ALTER TABLE matches ADD COLUMN match_type TEXT DEFAULT 'trade'");
      } catch (e) {
        print("Error adding match_type to matches: \$e");
      }
      try {
        await db.execute("ALTER TABLE matches ADD COLUMN notes TEXT DEFAULT ''");
      } catch (e) {
        print("Error adding notes to matches: \$e");
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS candles (
            exchange TEXT NOT NULL,
            symbol TEXT NOT NULL,
            interval TEXT NOT NULL,
            time INTEGER NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL DEFAULT 0.0,
            PRIMARY KEY (exchange, symbol, interval, time)
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_candles_lookup ON candles(exchange, symbol, interval, time)');
      } catch (e) {
        print("Error upgrading DB to v6: \$e");
      }
    }
  }

  // --- Candlesticks (Velas) Persistence ---

  Future<void> saveCandles({
    required String exchange,
    required String symbol,
    required String interval,
    required List<Map<String, dynamic>> candles,
  }) async {
    if (candles.isEmpty) return;
    final db = await instance.database;
    final ex = exchange.toLowerCase();
    final sym = symbol.toUpperCase();

    final batch = db.batch();
    for (final c in candles) {
      final int timeVal = (c['time'] is int)
          ? c['time'] as int
          : (c['time'] as num).toInt();
      final double openVal = (c['open'] as num).toDouble();
      final double highVal = (c['high'] as num).toDouble();
      final double lowVal = (c['low'] as num).toDouble();
      final double closeVal = (c['close'] as num).toDouble();
      final double volVal = c['volume'] != null ? (c['volume'] as num).toDouble() : 0.0;

      batch.rawInsert('''
        INSERT OR REPLACE INTO candles (exchange, symbol, interval, time, open, high, low, close, volume)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [ex, sym, interval, timeVal, openVal, highVal, lowVal, closeVal, volVal]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCandles({
    required String exchange,
    required String symbol,
    required String interval,
    int limit = 1500,
    int? beforeTimeSec,
  }) async {
    final db = await instance.database;
    final ex = exchange.toLowerCase();
    final sym = symbol.toUpperCase();

    final List<Map<String, Object?>> result;
    if (beforeTimeSec != null) {
      result = await db.rawQuery('''
        SELECT time, open, high, low, close, volume
        FROM candles
        WHERE exchange = ? AND symbol = ? AND interval = ? AND time <= ?
        ORDER BY time DESC
        LIMIT ?
      ''', [ex, sym, interval, beforeTimeSec, limit]);
    } else {
      result = await db.rawQuery('''
        SELECT time, open, high, low, close, volume
        FROM candles
        WHERE exchange = ? AND symbol = ? AND interval = ?
        ORDER BY time DESC
        LIMIT ?
      ''', [ex, sym, interval, limit]);
    }

    if (result.isEmpty) return [];

    final list = result.map((row) => Map<String, dynamic>.from(row)).toList();
    return list.reversed.toList();
  }

  Future<int> getCandleCount({
    required String exchange,
    required String symbol,
    required String interval,
  }) async {
    final db = await instance.database;
    final ex = exchange.toLowerCase();
    final sym = symbol.toUpperCase();

    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM candles
      WHERE exchange = ? AND symbol = ? AND interval = ?
    ''', [ex, sym, interval]);

    if (result.isNotEmpty && result.first['count'] != null) {
      return Sqflite.firstIntValue(result) ?? 0;
    }
    return 0;
  }

  // --- General Settings DB Operations ---

  Future<String?> getGeneralSetting(String key, {String? defaultValue}) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'general_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return defaultValue;
  }

  Future<void> setGeneralSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'general_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> getAllGeneralSettings() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('general_settings');
    final Map<String, String> result = {};
    for (var m in maps) {
      result[m['key'] as String] = m['value'] as String;
    }
    return result;
  }

  // --- Transactions DB Operations ---

  Future<int> insertTransaction(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('transactions', row);
  }

  Future<List<Map<String, dynamic>>> queryAllTransactions() async {
    final db = await instance.database;
    return await db.query('transactions', orderBy: 'date DESC');
  }

  Future<List<Map<String, dynamic>>> queryUnmatchedTransactions(String symbol, String exchange) async {
    final db = await instance.database;
    return await db.query(
      'transactions',
      where: 'symbol = ? AND exchange = ? AND is_matched = 0',
      whereArgs: [symbol, exchange],
      orderBy: 'date ASC',
    );
  }

  Future<int> updateTransaction(Map<String, dynamic> row) async {
    final db = await instance.database;
    int id = row['id'];
    return await db.update('transactions', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // --- Matches DB Operations ---

  Future<int> insertMatch(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('matches', row);
  }

  Future<List<Map<String, dynamic>>> queryAllMatches() async {
    final db = await instance.database;
    // Perform a join to display full details about matched buys/sells/expenses
    return await db.rawQuery('''
      SELECT 
        m.id, 
        m.buy_transaction_id,
        m.sell_transaction_id,
        m.matched_amount, 
        m.profit, 
        m.date,
        m.withdrawal_id,
        m.match_type,
        m.notes,
        t_buy.price AS buy_price,
        t_sell.price AS sell_price,
        COALESCE(t_buy.symbol, w.currency) AS symbol,
        COALESCE(t_buy.exchange, w.exchange) AS exchange,
        w.description AS expense_description,
        w.category AS expense_category
      FROM matches m
      LEFT JOIN transactions t_buy ON m.buy_transaction_id = t_buy.id
      LEFT JOIN transactions t_sell ON m.sell_transaction_id = t_sell.id
      LEFT JOIN withdrawals w ON m.withdrawal_id = w.id
      ORDER BY m.date DESC
    ''');
  }

  Future<int> deleteMatch(int id) async {
    final db = await instance.database;
    return await db.delete('matches', where: 'id = ?', whereArgs: [id]);
  }

  // --- Drawings DB Operations ---

  Future<int> insertDrawing(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('drawings', row);
  }

  Future<List<Map<String, dynamic>>> queryDrawings(String symbol, String exchange) async {
    final db = await instance.database;
    return await db.query(
      'drawings',
      where: 'symbol = ? AND exchange = ?',
      whereArgs: [symbol, exchange],
    );
  }

  Future<int> deleteDrawing(int id) async {
    final db = await instance.database;
    return await db.delete('drawings', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateDrawingPrice(int id, double price) async {
    final db = await instance.database;
    return await db.update(
      'drawings',
      {'price': price},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteDrawingByPrice(String symbol, String exchange, double price) async {
    final db = await instance.database;
    return await db.delete(
      'drawings',
      where: 'symbol = ? AND exchange = ? AND ABS(price - ?) < 0.00001',
      whereArgs: [symbol, exchange, price],
    );
  }

  Future<int> clearDrawings(String symbol, String exchange) async {
    final db = await instance.database;
    return await db.delete(
      'drawings',
      where: 'symbol = ? AND exchange = ?',
      whereArgs: [symbol, exchange],
    );
  }

  // --- API Keys DB Operations ---

  Future<int> insertApiKey(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert(
      'api_keys',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> queryApiKey(String exchange) async {
    final db = await instance.database;
    final results = await db.query(
      'api_keys',
      where: 'LOWER(exchange) = ?',
      whereArgs: [exchange.toLowerCase()],
    );
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getApiKey(String exchange) => queryApiKey(exchange);

  Future<int> deleteApiKey(String exchange) async {
    final db = await instance.database;
    return await db.delete('api_keys', where: 'exchange = ?', whereArgs: [exchange]);
  }

  // --- API Sync DB Operations ---

  Future<DateTime?> getLastSyncDate(String exchange, String symbol) async {
    final db = await instance.database;
    final results = await db.query(
      'api_sync',
      where: 'exchange = ? AND symbol = ?',
      whereArgs: [exchange, symbol],
    );
    if (results.isNotEmpty) {
      final dateStr = results.first['last_sync_date'] as String;
      return DateTime.parse(dateStr);
    }
    return null;
  }

  Future<void> updateLastSyncDate(String exchange, String symbol, DateTime date) async {
    final db = await instance.database;
    await db.insert(
      'api_sync',
      {
        'exchange': exchange,
        'symbol': symbol,
        'last_sync_date': date.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Favorites DB Operations ---

  Future<List<String>> queryFavorites() async {
    final db = await instance.database;
    final results = await db.query('favorites');
    return results.map((row) => row['symbol'] as String).toList();
  }

  Future<void> addFavorite(String symbol) async {
    final db = await instance.database;
    await db.insert(
      'favorites',
      {'symbol': symbol},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeFavorite(String symbol) async {
    final db = await instance.database;
    await db.delete('favorites', where: 'symbol = ?', whereArgs: [symbol]);
  }

  // --- Exchange Settings DB Operations ---

  Future<double> getDefaultBuyAmount(String exchange) async {
    final db = await instance.database;
    final results = await db.query(
      'exchange_settings',
      where: 'exchange = ?',
      whereArgs: [exchange],
    );
    if (results.isNotEmpty) {
      return (results.first['default_buy_amount'] as num).toDouble();
    }
    return 100.0;
  }

  Future<void> setDefaultBuyAmount(String exchange, double amount) async {
    final db = await instance.database;
    await db.insert(
      'exchange_settings',
      {
        'exchange': exchange,
        'default_buy_amount': amount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Withdrawals & Expenses DB Operations ---

  Future<int> insertWithdrawal(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('withdrawals', row);
  }

  Future<int> updateWithdrawal(Map<String, dynamic> row) async {
    final db = await instance.database;
    final id = row['id'] as int;
    return await db.update('withdrawals', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteWithdrawal(int id) async {
    final db = await instance.database;
    return await db.delete('withdrawals', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> queryAllWithdrawals() async {
    final db = await instance.database;
    return await db.query('withdrawals', orderBy: 'date DESC');
  }

  Future<List<Map<String, dynamic>>> queryWithdrawalsByExchange(String exchange) async {
    final db = await instance.database;
    return await db.query(
      'withdrawals',
      where: 'exchange = ?',
      whereArgs: [exchange],
      orderBy: 'date DESC',
    );
  }

  // --- Backup & Restore DB Operations ---

  Future<String> getDatabasePath() async {
    if (!kIsWeb && Platform.isWindows) {
      final directory = await getApplicationSupportDirectory();
      return join(directory.path, 'CryptoView', 'cryptoview.db');
    } else {
      final dbPath = await getDatabasesPath();
      return join(dbPath, 'cryptoview.db');
    }
  }

  Future<String> getBackupsDirectoryPath() async {
    if (!kIsWeb && Platform.isWindows) {
      final directory = await getApplicationSupportDirectory();
      final backupDir = Directory(join(directory.path, 'CryptoView', 'Backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      return backupDir.path;
    } else {
      final dbPath = await getDatabasesPath();
      final backupDir = Directory(join(dbPath, 'Backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      return backupDir.path;
    }
  }

  Future<String> createBackup() async {
    final db = await database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(FULL);');
    } catch (_) {}

    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('El archivo de base de datos no existe.');
    }

    final backupDirPath = await getBackupsDirectoryPath();
    final now = DateTime.now().toUtc();
    final pad = (int n) => n.toString().padLeft(2, '0');
    final filename = 'cryptoview_backup_${now.year}-${pad(now.month)}-${pad(now.day)}_${pad(now.hour)}-${pad(now.minute)}-${pad(now.second)}.db';
    final backupFile = File(join(backupDirPath, filename));

    await dbFile.copy(backupFile.path);
    return backupFile.path;
  }

  Future<List<File>> getBackupFiles() async {
    final backupDirPath = await getBackupsDirectoryPath();
    final dir = Directory(backupDirPath);
    if (!await dir.exists()) return [];

    final entities = await dir.list().toList();
    final files = entities
        .whereType<File>()
        .where((f) => f.path.endsWith('.db') || f.path.endsWith('.json.gz') || f.path.endsWith('.sql.gz'))
        .toList();
    files.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
    return files;
  }

  Future<void> restoreBackup(String backupFilePath) async {
    final backupFile = File(backupFilePath);
    if (!await backupFile.exists()) {
      throw Exception('El archivo de respaldo seleccionado no existe.');
    }

    // 1. Close current DB connection
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);

    // 2. Safety copy of current DB before overwrite
    if (await dbFile.exists()) {
      final backupDirPath = await getBackupsDirectoryPath();
      final preRestoreName = 'cryptoview_pre_restore_${DateTime.now().millisecondsSinceEpoch}.db';
      try {
        await dbFile.copy(join(backupDirPath, preRestoreName));
      } catch (_) {}
    }

    // 3. Overwrite current DB with selected backup
    await backupFile.copy(dbPath);

    // 4. Reopen database connection
    _database = await _initDB('cryptoview.db');
  }

  /// Exporta todas las tablas de trabajo del usuario en SQLite (compras/ventas, casamientos,
  /// gastos/retiros, dibujos del gráfico, favoritas, ajustes y llaves) en un mapa serializable a JSON.
  Future<Map<String, dynamic>> exportAllLocalTables() async {
    final db = await database;
    return {
      'transactions': await db.query('transactions', orderBy: 'id ASC'),
      'matches': await db.query('matches', orderBy: 'id ASC'),
      'withdrawals': await db.query('withdrawals', orderBy: 'id ASC'),
      'drawings': await db.query('drawings', orderBy: 'id ASC'),
      'favorites': await db.query('favorites'),
      'exchange_settings': await db.query('exchange_settings'),
      'general_settings': await db.query('general_settings'),
      'api_sync': await db.query('api_sync'),
      'api_keys': await db.query('api_keys'),
    };
  }

  /// Restaura todas las tablas locales de SQLite desde un mapa JSON exportado previamente,
  /// preservando los IDs originales para mantener intactos todos los casamientos (matches).
  Future<void> restoreAllLocalTables(Map<String, dynamic> localData) async {
    if (localData.isEmpty) return;

    // 1. Copia preventiva del archivo .db actual antes de restaurar
    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final backupDirPath = await getBackupsDirectoryPath();
      final preRestoreName = 'cryptoview_pre_restore_${DateTime.now().millisecondsSinceEpoch}.db';
      try {
        await dbFile.copy(join(backupDirPath, preRestoreName));
      } catch (_) {}
    }

    final db = await database;
    await db.transaction((txn) async {
      Future<void> restoreTable(String tableName, List<dynamic>? rows, {bool clearExisting = true}) async {
        if (rows == null) return;
        if (clearExisting) {
          await txn.delete(tableName);
        }
        for (final rawRow in rows) {
          if (rawRow is Map) {
            final row = Map<String, dynamic>.from(rawRow);
            await txn.insert(
              tableName,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }

      // Restaurar en orden de integridad referencial
      if (localData.containsKey('transactions')) {
        await restoreTable('transactions', localData['transactions'] as List<dynamic>?);
      }
      if (localData.containsKey('withdrawals')) {
        await restoreTable('withdrawals', localData['withdrawals'] as List<dynamic>?);
      }
      if (localData.containsKey('matches')) {
        await restoreTable('matches', localData['matches'] as List<dynamic>?);
      }
      if (localData.containsKey('drawings')) {
        await restoreTable('drawings', localData['drawings'] as List<dynamic>?);
      }
      if (localData.containsKey('favorites')) {
        await restoreTable('favorites', localData['favorites'] as List<dynamic>?);
      }
      if (localData.containsKey('exchange_settings')) {
        await restoreTable('exchange_settings', localData['exchange_settings'] as List<dynamic>?, clearExisting: false);
      }
      if (localData.containsKey('general_settings')) {
        await restoreTable('general_settings', localData['general_settings'] as List<dynamic>?, clearExisting: false);
      }
      if (localData.containsKey('api_sync')) {
        await restoreTable('api_sync', localData['api_sync'] as List<dynamic>?, clearExisting: false);
      }
      if (localData.containsKey('api_keys')) {
        final keysList = localData['api_keys'] as List<dynamic>?;
        if (keysList != null && keysList.isNotEmpty) {
          await restoreTable('api_keys', keysList, clearExisting: false);
        }
      }
    });
  }

  Future<void> deleteBackup(String backupFilePath) async {
    final file = File(backupFilePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> openBackupsFolder() async {
    final path = await getBackupsDirectoryPath();
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [path]);
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}
