import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'dim_settings.dart';

/// Persists [DimSettings] as JSON in the app support directory so both the
/// main isolate and the background overlay isolate share the same config.
class SettingsStore {
  SettingsStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const String _fileName = 'darkplus_settings.json';
  final Future<Directory> Function() _directoryProvider;

  Future<File> _resolveFile() async {
    final dir = await _directoryProvider();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<DimSettings> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) {
        return const DimSettings();
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DimSettings.fromMap(decoded);
      }
    } catch (_) {
      // Fall back to defaults on corrupt or unreadable files.
    }
    return const DimSettings();
  }

  Future<void> save(DimSettings settings) async {
    try {
      final file = await _resolveFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(settings.toMap()), flush: true);
    } catch (_) {
      // Best-effort persistence; UI/live overlay still works in-memory.
    }
  }
}
