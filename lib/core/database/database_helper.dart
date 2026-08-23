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
      version: 2,
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
        sell_transaction_id INTEGER NOT NULL,
        matched_amount REAL NOT NULL,
        profit REAL NOT NULL,
        date TEXT NOT NULL,
        FOREIGN KEY (buy_transaction_id) REFERENCES transactions (id) ON DELETE CASCADE,
        FOREIGN KEY (sell_transaction_id) REFERENCES transactions (id) ON DELETE CASCADE
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
    // Perform a join to display full details about matched buys/sells
    return await db.rawQuery('''
      SELECT 
        m.id, 
        m.buy_transaction_id,
        m.sell_transaction_id,
        m.matched_amount, 
        m.profit, 
        m.date,
        t_buy.price AS buy_price,
        t_sell.price AS sell_price,
        t_buy.symbol,
        t_buy.exchange
      FROM matches m
      JOIN transactions t_buy ON m.buy_transaction_id = t_buy.id
      JOIN transactions t_sell ON m.sell_transaction_id = t_sell.id
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
      where: 'exchange = ?',
      whereArgs: [exchange],
    );
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

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
        'last_sync_date': date.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}
