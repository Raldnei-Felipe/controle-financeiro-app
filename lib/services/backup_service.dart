import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class BackupService {
  Future<String> _databaseFilePath() async {
    final databasesPath = await getDatabasesPath();
    return p.join(databasesPath, 'app_financeiro.db');
  }

  Future<void> createAndShareBackup() async {
    final dbPath = await _databaseFilePath();
    final databaseFile = File(dbPath);

    if (!await databaseFile.exists()) {
      throw StateError('Banco de dados não encontrado.');
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    final backupFile = File(
      '${documentsDirectory.path}/'
      'backup_financas_$timestamp.db',
    );

    await backupFile.writeAsBytes(await databaseFile.readAsBytes());

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(backupFile.path)],
        text: 'Backup do app financeiro',
      ),
    );
  }

  Future<void> restoreFromBackup() async {
    final result = await FilePicker.pickFile(type: FileType.any);

    final pickedPath = result?.path;

    if (pickedPath == null) {
      return;
    }

    final pickedFile = File(pickedPath);

    if (!await pickedFile.exists()) {
      throw StateError('Arquivo não encontrado.');
    }

    final bytes = await pickedFile.readAsBytes();
    final header = String.fromCharCodes(bytes.take(15));

    if (header != 'SQLite format 3') {
      throw StateError('Este arquivo não é um backup válido do app.');
    }

    final dbPath = await _databaseFilePath();

    await AppDatabase.instance.close();

    final temporaryPath = '$dbPath.restoring';
    final temporaryFile = File(temporaryPath);

    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }

    await pickedFile.copy(temporaryPath);

    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    final walFile = File('$dbPath-wal');

    if (await walFile.exists()) {
      await walFile.delete();
    }

    final shmFile = File('$dbPath-shm');

    if (await shmFile.exists()) {
      await shmFile.delete();
    }

    await temporaryFile.rename(dbPath);
  }
}
