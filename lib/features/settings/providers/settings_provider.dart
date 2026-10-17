import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' show join;
import '../../../core/database/database_helper.dart';

class SettingsProvider with ChangeNotifier {
  // Default values
  static const String defaultBuyLineColor = '#00E676'; // Neon Green
  static const String defaultSellLineColor = '#FF5252'; // Neon Red
  static const String defaultCurrentPriceColor = '#00E5FF'; // Electric Cyan
  static const String defaultCloudApiUrl = 'http://129.146.110.196:8000';
  static const String defaultCloudApiToken = 'aa0d07ca7079caf19492d0fc4a762c593b3e02e205c669ae60de5cbbd66979c2';

  String _buyLineColorHex = defaultBuyLineColor;
  String _sellLineColorHex = defaultSellLineColor;
  String _currentPriceColorHex = defaultCurrentPriceColor;
  String _cloudApiUrl = defaultCloudApiUrl;
  String _cloudApiToken = defaultCloudApiToken;

  bool _showBuyLines = true;
  bool _showBuyLabels = true;
  bool _showSellLines = true;
  bool _showSellLabels = true;
  bool _showOpenOrders = true;
  bool _showOpenOrderLabels = true;
  bool _showDrawings = true;
  bool _showDrawingLabels = true;
  bool _showCurrentPriceLine = true;
  bool _showCurrentPriceLabel = true;

  double _watchlistWidth = 300.0;
  double _trackerWidth = 380.0;

  bool _isLoaded = false;
  List<File> _backupFiles = [];
  bool _isBackupBusy = false;
  String? _backupMessage;

  SettingsProvider() {
    loadSettings();
  }

  List<File> get backupFiles => _backupFiles;
  bool get isBackupBusy => _isBackupBusy;
  String? get backupMessage => _backupMessage;

  DateTime? get lastBackupDate {
    if (_backupFiles.isEmpty) return null;
    try {
      return _backupFiles.first.lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  int? get daysSinceLastBackup {
    final last = lastBackupDate;
    if (last == null) return null;
    return DateTime.now().difference(last).inDays;
  }

  bool get isBackupOverdue {
    final days = daysSinceLastBackup;
    return days == null || days >= 30;
  }

  String get buyLineColorHex => _buyLineColorHex;
  String get sellLineColorHex => _sellLineColorHex;
  String get currentPriceColorHex => _currentPriceColorHex;

  bool get showBuyLines => _showBuyLines;
  bool get showBuyLabels => _showBuyLabels;
  bool get showSellLines => _showSellLines;
  bool get showSellLabels => _showSellLabels;
  bool get showOpenOrders => _showOpenOrders;
  bool get showOpenOrderLabels => _showOpenOrderLabels;
  bool get showDrawings => _showDrawings;
  bool get showDrawingLabels => _showDrawingLabels;
  bool get showCurrentPriceLine => _showCurrentPriceLine;
  bool get showCurrentPriceLabel => _showCurrentPriceLabel;

  bool get areAllLabelsVisible =>
      _showBuyLabels && _showSellLabels && _showOpenOrderLabels && _showDrawingLabels && _showCurrentPriceLabel;

  bool get hasAnyLabelVisible =>
      _showBuyLabels || _showSellLabels || _showOpenOrderLabels || _showDrawingLabels || _showCurrentPriceLabel;

  bool get areAllLinesVisible =>
      _showBuyLines && _showSellLines && _showOpenOrders && _showDrawings && _showCurrentPriceLine;

  bool get hasAnyLineVisible =>
      _showBuyLines || _showSellLines || _showOpenOrders || _showDrawings || _showCurrentPriceLine;

  double get watchlistWidth => _watchlistWidth;
  double get trackerWidth => _trackerWidth;
  bool get isLoaded => _isLoaded;

  Color get buyLineColor => _parseColor(_buyLineColorHex, const Color(0xFF00E676));
  Color get sellLineColor => _parseColor(_sellLineColorHex, const Color(0xFFFF5252));
  Color get currentPriceColor => _parseColor(_currentPriceColorHex, const Color(0xFF00E5FF));

  Color _parseColor(String hexString, Color fallback) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Future<void> loadSettings() async {
    try {
      final db = DatabaseHelper.instance;
      _buyLineColorHex = await db.getGeneralSetting('buy_line_color', defaultValue: defaultBuyLineColor) ?? defaultBuyLineColor;
      _sellLineColorHex = await db.getGeneralSetting('sell_line_color', defaultValue: defaultSellLineColor) ?? defaultSellLineColor;
      _currentPriceColorHex = await db.getGeneralSetting('current_price_color', defaultValue: defaultCurrentPriceColor) ?? defaultCurrentPriceColor;

      _showBuyLines = (await db.getGeneralSetting('show_buy_lines', defaultValue: '1')) == '1';
      _showBuyLabels = (await db.getGeneralSetting('show_buy_labels', defaultValue: '1')) == '1';

      _showSellLines = (await db.getGeneralSetting('show_sell_lines', defaultValue: '1')) == '1';
      _showSellLabels = (await db.getGeneralSetting('show_sell_labels', defaultValue: '1')) == '1';

      _showOpenOrders = (await db.getGeneralSetting('show_open_orders', defaultValue: '1')) == '1';
      _showOpenOrderLabels = (await db.getGeneralSetting('show_open_order_labels', defaultValue: '1')) == '1';

      _showDrawings = (await db.getGeneralSetting('show_drawings', defaultValue: '1')) == '1';
      _showDrawingLabels = (await db.getGeneralSetting('show_drawing_labels', defaultValue: '1')) == '1';

      _showCurrentPriceLine = (await db.getGeneralSetting('show_current_price_line', defaultValue: '1')) == '1';
      _showCurrentPriceLabel = (await db.getGeneralSetting('show_current_price_label', defaultValue: '1')) == '1';

      final wWidthStr = await db.getGeneralSetting('watchlist_width', defaultValue: '300.0');
      _watchlistWidth = double.tryParse(wWidthStr ?? '300.0') ?? 300.0;

      final tWidthStr = await db.getGeneralSetting('tracker_width', defaultValue: '380.0');
      _trackerWidth = double.tryParse(tWidthStr ?? '380.0') ?? 380.0;

      await loadBackups();

      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> loadBackups() async {
    try {
      _backupFiles = await DatabaseHelper.instance.getBackupFiles();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading backups: $e');
    }
  }

  Future<String?> createBackup() async {
    _isBackupBusy = true;
    _backupMessage = null;
    notifyListeners();

    try {
      final path = await DatabaseHelper.instance.createBackup();
      await loadBackups();
      _isBackupBusy = false;
      _backupMessage = 'Copia de seguridad local (.db) creada correctamente.';
      notifyListeners();
      return path;
    } catch (e) {
      _isBackupBusy = false;
      _backupMessage = 'Error creando salva local: $e';
      notifyListeners();
      return null;
    }
  }

  Future<String?> downloadCloudBackup({bool includeCandles = false}) async {
    _isBackupBusy = true;
    _backupMessage = null;
    notifyListeners();

    try {
      // 1. Descargar los datos del Servidor Cloud hacia tu PC
      final uri = Uri.parse(
        '$_cloudApiUrl/api/v1/backup/export?include_candles=$includeCandles&compressed=true',
      );
      final response = await http.get(
        uri,
        headers: {'X-API-Key': _cloudApiToken},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      // 2. Leer también todas las tablas locales de SQLite en tu PC y unirlas en el mismo archivo local .json.gz
      final localSqlite = await DatabaseHelper.instance.exportAllLocalTables();
      List<int> finalGzBytes = response.bodyBytes;
      try {
        final rawBytes = response.bodyBytes;
        final decompressed = (rawBytes.length >= 2 && rawBytes[0] == 0x1F && rawBytes[1] == 0x8B)
            ? gzip.decode(rawBytes)
            : rawBytes;
        final payload = jsonDecode(utf8.decode(decompressed)) as Map<String, dynamic>;
        final data = (payload['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        data['local_sqlite'] = localSqlite;
        payload['data'] = data;
        final counts = (payload['counts'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        counts['local_transactions'] = (localSqlite['transactions'] as List?)?.length ?? 0;
        counts['local_matches'] = (localSqlite['matches'] as List?)?.length ?? 0;
        counts['local_withdrawals'] = (localSqlite['withdrawals'] as List?)?.length ?? 0;
        counts['local_drawings'] = (localSqlite['drawings'] as List?)?.length ?? 0;
        payload['counts'] = counts;
        finalGzBytes = gzip.encode(utf8.encode(jsonEncode(payload)));
      } catch (_) {}

      final backupDirPath = await DatabaseHelper.instance.getBackupsDirectoryPath();
      final now = DateTime.now().toUtc();
      final pad = (int n) => n.toString().padLeft(2, '0');
      final suffix = includeCandles ? 'full' : 'privado';
      final filename =
          'cryptoview_cloud_${suffix}_${now.year}-${pad(now.month)}-${pad(now.day)}_${pad(now.hour)}-${pad(now.minute)}-${pad(now.second)}.json.gz';
      final file = File(join(backupDirPath, filename));
      await file.writeAsBytes(finalGzBytes, flush: true);

      await loadBackups();
      _isBackupBusy = false;
      _backupMessage = 'Salva completa (Local + Servidor Cloud) guardada con éxito.';
      notifyListeners();
      return file.path;
    } catch (e) {
      _isBackupBusy = false;
      _backupMessage = 'Error descargando salva del servidor: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> restoreBackup(String path) async {
    _isBackupBusy = true;
    _backupMessage = null;
    notifyListeners();

    try {
      if (path.endsWith('.json.gz') || path.endsWith('.json')) {
        final bytes = await File(path).readAsBytes();

        // 1. Extraer local_sqlite del archivo de respaldo para restaurar SQLite local
        Map<String, dynamic> localSqlite = {};
        try {
          final decompressed = (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B)
              ? gzip.decode(bytes)
              : bytes;
          final payload = jsonDecode(utf8.decode(decompressed)) as Map<String, dynamic>;
          final data = payload['data'] as Map<String, dynamic>?;
          if (data != null && data['local_sqlite'] is Map) {
            localSqlite = Map<String, dynamic>.from(data['local_sqlite'] as Map);
          }
        } catch (e) {
          debugPrint('Error leyendo local_sqlite del respaldo: $e');
        }

        // 2. Restaurar en el Servidor Cloud (PostgreSQL)
        final uri = Uri.parse('$_cloudApiUrl/api/v1/backup/restore');
        final response = await http.post(
          uri,
          headers: {
            'X-API-Key': _cloudApiToken,
            'Content-Type': 'application/octet-stream',
          },
          body: bytes,
        ).timeout(const Duration(seconds: 90));

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }

        // Si el archivo no traía local_sqlite pero el servidor lo devolvió en la respuesta
        if (localSqlite.isEmpty) {
          try {
            final respJson = jsonDecode(response.body) as Map<String, dynamic>;
            if (respJson['local_sqlite'] is Map) {
              localSqlite = Map<String, dynamic>.from(respJson['local_sqlite'] as Map);
            }
          } catch (_) {}
        }

        // 3. Restaurar todas las tablas de SQLite local (compras, ventas, casamientos, Bitrefill, dibujos, favoritas, ajustes)
        if (localSqlite.isNotEmpty) {
          await DatabaseHelper.instance.restoreAllLocalTables(localSqlite);
        }

        await loadSettings();
        await loadBackups();
        _isBackupBusy = false;
        _backupMessage = 'Base de datos Local y Servidor Cloud restaurados correctamente.';
        notifyListeners();
        return true;
      }

      await DatabaseHelper.instance.restoreBackup(path);
      await loadSettings();
      await loadBackups();
      _isBackupBusy = false;
      _backupMessage = 'Base de datos local restaurada correctamente.';
      notifyListeners();
      return true;
    } catch (e) {
      _isBackupBusy = false;
      _backupMessage = 'Error restaurando salva: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteBackup(String path) async {
    try {
      await DatabaseHelper.instance.deleteBackup(path);
      await loadBackups();
    } catch (e) {
      debugPrint('Error deleting backup: $e');
    }
  }

  Future<void> openBackupsFolder() async {
    try {
      await DatabaseHelper.instance.openBackupsFolder();
    } catch (e) {
      debugPrint('Error opening backups folder: $e');
    }
  }

  Future<void> setWatchlistWidth(double w) async {
    _watchlistWidth = w.clamp(180.0, 550.0);
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('watchlist_width', _watchlistWidth.toStringAsFixed(1));
  }

  Future<void> setTrackerWidth(double w) async {
    _trackerWidth = w.clamp(240.0, 700.0);
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('tracker_width', _trackerWidth.toStringAsFixed(1));
  }

  Future<void> setBuyLineColor(String hex) async {
    _buyLineColorHex = hex;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('buy_line_color', hex);
  }

  Future<void> setSellLineColor(String hex) async {
    _sellLineColorHex = hex;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('sell_line_color', hex);
  }

  Future<void> setCurrentPriceColor(String hex) async {
    _currentPriceColorHex = hex;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('current_price_color', hex);
  }

  Future<void> setShowBuyLines(bool show) async {
    _showBuyLines = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_buy_lines', show ? '1' : '0');
  }

  Future<void> setShowBuyLabels(bool show) async {
    _showBuyLabels = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_buy_labels', show ? '1' : '0');
  }

  Future<void> setShowSellLines(bool show) async {
    _showSellLines = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_sell_lines', show ? '1' : '0');
  }

  Future<void> setShowSellLabels(bool show) async {
    _showSellLabels = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_sell_labels', show ? '1' : '0');
  }

  Future<void> setShowOpenOrders(bool show) async {
    _showOpenOrders = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_open_orders', show ? '1' : '0');
  }

  Future<void> setShowOpenOrderLabels(bool show) async {
    _showOpenOrderLabels = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_open_order_labels', show ? '1' : '0');
  }

  Future<void> setShowDrawings(bool show) async {
    _showDrawings = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_drawings', show ? '1' : '0');
  }

  Future<void> setShowDrawingLabels(bool show) async {
    _showDrawingLabels = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_drawing_labels', show ? '1' : '0');
  }

  Future<void> setShowCurrentPriceLine(bool show) async {
    _showCurrentPriceLine = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_current_price_line', show ? '1' : '0');
  }

  Future<void> setShowCurrentPriceLabel(bool show) async {
    _showCurrentPriceLabel = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_current_price_label', show ? '1' : '0');
  }

  /// Master switch: Toggle all labels (text) ON or OFF across all line categories with 1 click
  Future<void> toggleAllLabels(bool show) async {
    _showBuyLabels = show;
    _showSellLabels = show;
    _showOpenOrderLabels = show;
    _showDrawingLabels = show;
    _showCurrentPriceLabel = show;
    notifyListeners();

    final db = DatabaseHelper.instance;
    final val = show ? '1' : '0';
    await db.setGeneralSetting('show_buy_labels', val);
    await db.setGeneralSetting('show_sell_labels', val);
    await db.setGeneralSetting('show_open_order_labels', val);
    await db.setGeneralSetting('show_drawing_labels', val);
    await db.setGeneralSetting('show_current_price_label', val);
  }

  /// Master switch: Toggle all lines ON or OFF across all categories with 1 click
  Future<void> toggleAllLines(bool show) async {
    _showBuyLines = show;
    _showSellLines = show;
    _showOpenOrders = show;
    _showDrawings = show;
    _showCurrentPriceLine = show;
    notifyListeners();

    final db = DatabaseHelper.instance;
    final val = show ? '1' : '0';
    await db.setGeneralSetting('show_buy_lines', val);
    await db.setGeneralSetting('show_sell_lines', val);
    await db.setGeneralSetting('show_open_orders', val);
    await db.setGeneralSetting('show_drawings', val);
    await db.setGeneralSetting('show_current_price_line', val);
  }

  Future<void> resetToDefaults() async {
    _buyLineColorHex = defaultBuyLineColor;
    _sellLineColorHex = defaultSellLineColor;
    _currentPriceColorHex = defaultCurrentPriceColor;
    _showBuyLines = true;
    _showBuyLabels = true;
    _showSellLines = true;
    _showSellLabels = true;
    _showOpenOrders = true;
    _showOpenOrderLabels = true;
    _showCurrentPriceLine = true;
    _showCurrentPriceLabel = true;
    _showDrawings = true;
    _showDrawingLabels = true;
    notifyListeners();

    final db = DatabaseHelper.instance;
    await db.setGeneralSetting('buy_line_color', defaultBuyLineColor);
    await db.setGeneralSetting('sell_line_color', defaultSellLineColor);
    await db.setGeneralSetting('current_price_color', defaultCurrentPriceColor);
    await db.setGeneralSetting('show_buy_lines', '1');
    await db.setGeneralSetting('show_buy_labels', '1');
    await db.setGeneralSetting('show_sell_lines', '1');
    await db.setGeneralSetting('show_sell_labels', '1');
    await db.setGeneralSetting('show_open_orders', '1');
    await db.setGeneralSetting('show_open_order_labels', '1');
    await db.setGeneralSetting('show_current_price_line', '1');
    await db.setGeneralSetting('show_current_price_label', '1');
    await db.setGeneralSetting('show_drawings', '1');
    await db.setGeneralSetting('show_drawing_labels', '1');
  }
}
