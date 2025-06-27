import "dart:convert";
import "dart:io";

import "package:cryptography_plus/cryptography_plus.dart";
import "package:desktop_updater/src/app_archive.dart";

Future<String> getFileHash(File file) async {
  try {
    final List<int> fileBytes = await file.readAsBytes();
    final hash = await Blake2b().hash(fileBytes);
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

  if (await dir.exists()) {
    final outputFile = File("${dir.path}${Platform.pathSeparator}hashes.json");
    final sink = outputFile.openWrite();
    var hashList = <FileHashModel>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          !entity.path.endsWith("hashes.json") &&
          !entity.path.endsWith(".DS_Store")) {
        final hash = await getFileHash(entity);
        final foundPath = entity.path.substring(dir.path.length + 1);

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

    final jsonStr = jsonEncode(hashList);
    sink.write(jsonStr);
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
  if (!['macos', 'windows', 'linux'].contains(platform)) {
    print("Invalid PLATFORM: must be macos, windows, or linux");
    exit(1);
  }

  final buildDir = Directory("build/$platform/Build/Products/Release");
  if (!await buildDir.exists()) {
    print("Build directory not found for platform: $platform");
    exit(1);
  }

  final pubspec = File("pubspec.yaml");
  final pubspecContent = await pubspec.readAsString();
  final versionMatch = RegExp(r'version:\s*(\S+)').firstMatch(pubspecContent);
  final nameMatch = RegExp(r'name:\s*(\S+)').firstMatch(pubspecContent);

  if (versionMatch == null || nameMatch == null) {
    print("Failed to read name/version from pubspec.yaml");
    exit(1);
  }

  final version = versionMatch.group(1)!;
  final appName = nameMatch.group(1)!;
  final distDir = Directory("dist/$version");
  await distDir.create(recursive: true);

  Directory? targetDir;
  if (platform == 'macos') {
    final appDirs = buildDir.listSync().whereType<Directory>()
        .where((d) => d.path.endsWith(".app"));
    if (appDirs.isEmpty) {
      print("No .app directory found in macOS build folder");
      exit(1);
    }
    targetDir = Directory("${appDirs.first.path}/Contents");
  } else {
    targetDir = buildDir;
  }

  await genFileHashes(path: targetDir.path);
  final outputFile = File("${distDir.path}/${platform}-hashes.json");
  final sourceHashes = File("${targetDir.path}/hashes.json");
  await sourceHashes.copy(outputFile.path);
  await sourceHashes.delete();

  print("✅ Hashes saved to ${outputFile.path}");
}
