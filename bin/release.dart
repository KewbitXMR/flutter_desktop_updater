import "dart:convert";
import "dart:io";

import "package:cryptography_plus/cryptography_plus.dart";
import "package:desktop_updater/src/app_archive.dart";
import "package:path/path.dart" as path;
import "package:pubspec_parse/pubspec_parse.dart";

import "helper/copy.dart";

Future<String> getFileHash(File file) async {
  try {
    // Dosya içeriğini okuyun
    final List<int> fileBytes = await file.readAsBytes();

    // blake2s algoritmasıyla hash hesaplayın

    final hash = await Blake2b().hash(fileBytes);

    // Hash'i utf-8 base64'e dönüştürün ve geri döndürün
    return base64.encode(hash.bytes);
  } catch (e) {
    print("Error reading file ${file.path}: $e");
    return "";
  }
}

Future<String?> genFileHashes({required String? path}) async {
  print("Generating file hashes for $path");

  if (path == null) {
    throw Exception("Desktop Updater: Executable path is null");
  }

  final dir = Directory(path);

  print("Directory path: ${dir.path}");

  // Eğer belirtilen yol bir dizinse
  if (await dir.exists()) {
    // temp dizinindeki dosyaları kopyala
    // dir + output.txt dosyası oluşturulur
    final outputFile = File("${dir.path}${Platform.pathSeparator}hashes.json");

    // Çıktı dosyasını açıyoruz
    final sink = outputFile.openWrite();

    // ignore: prefer_final_locals
    var hashList = <FileHashModel>[];

    // Dizin içindeki tüm dosyaları döngüyle okuyoruz
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          !entity.path.endsWith("hashes.json") &&
          !entity.path.endsWith(".DS_Store")) {
        // Dosyanın hash'ini al
        final hash = await getFileHash(entity);
        final foundPath = entity.path.substring(dir.path.length + 1);

        // Dosya yolunu ve hash değerini yaz
        if (hash.isNotEmpty) {
          final hashObj = FileHashModel(
            filePath: foundPath,
            calculatedHash: hash,
            length: entity.lengthSync(),
          );
          hashList.add(hashObj);
        }
      }
    }

    // Dosya hash'lerini json formatına çevir
    final jsonStr = jsonEncode(hashList);

    // Çıktı dosyasına yaz
    sink.write(jsonStr);

    // Çıktıyı kaydediyoruz
    await sink.close();
    return outputFile.path;
  } else {
    throw Exception("Desktop Updater: Directory does not exist");
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print("PLATFORM must be specified: macos, windows, linux");
    exit(1);
  }

  final platform = args[0];

  if (platform != "macos" && platform != "windows" && platform != "linux") {
    print("PLATFORM must be specified: macos, windows, linux");
    exit(1);
  }

  final pubspec = File("pubspec.yaml").readAsStringSync();
  final parsed = Pubspec.parse(pubspec);

  /// Only base version 1.0.0
  final buildName = "${parsed.version?.major}.${parsed.version?.minor}.${parsed.version?.patch}";

  // Go to dist directory and get all folder names
  final distStagedDir = Directory("dist/updater/staged/");
  final distReleaseDir = Directory("dist/updater/release/");

  if (!await distStagedDir.exists()) {
    print("You must first run 'dart run desktop_updater:prepare $platform' to prepare the files.");
    exit(1);
  }

  Directory? bundleReleaseDestDir;

  if (platform == "windows") {
    bundleReleaseDestDir = Directory(
      path.join(
        distReleaseDir.path,
        buildName,
        "$platform-bundle",
      ),
    );
    await copyDirectory(
      Directory(
        path.join(
          distStagedDir.path,
          buildName,
          "$platform-bundle",
        ),
      ),
      bundleReleaseDestDir,
    );
  } else if (platform == "macos") {
    bundleReleaseDestDir = Directory(
      path.join(
        distReleaseDir.path,
        buildName,
        "$platform-bundle",
      ),
    );
    await copyDirectory(
      Directory(
        path.join(
          distStagedDir.path,
          buildName,
          "$platform-bundle",
        ),
      ),
      bundleReleaseDestDir,
    );
  } else if (platform == "linux") {
    bundleReleaseDestDir = Directory(
      path.join(
        distReleaseDir.path,
        buildName,
        "$platform-bundle",
      ),
    );
    await copyDirectory(
      Directory(
        path.join(
          distStagedDir.path,
          buildName,
          "$platform-bundle",
        ),
      ),
      bundleReleaseDestDir,
    );
  } else {
    print("Unsupported platform: $platform");
    exit(1);
  }

  await genFileHashes(
    path: bundleReleaseDestDir.path,
  );

  return;
}
