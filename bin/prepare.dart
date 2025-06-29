import "dart:convert";
import "dart:io";

import "package:path/path.dart" as path;
import "package:pubspec_parse/pubspec_parse.dart";

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
  final buildNumber = parsed.version?.build.firstOrNull.toString();

  print(
    "Building version $buildName+$buildNumber for $platform for app ${parsed.name}",
  );

  final appNamePubspec = parsed.name;

  // Get flutter path
  final flutterPath = Platform.environment["FLUTTER_ROOT"];

  if (flutterPath == null || flutterPath.isEmpty) {
    print("FLUTTER_ROOT environment variable is not set");
    exit(1);
  }

  // Print current working directory
  print("Current working directory: ${Directory.current.path}");

  // Determine the Flutter executable based on the platform
  var flutterExecutable = "flutter";
  if (Platform.isWindows) {
    flutterExecutable += ".bat";
  }

  final flutterBinPath = path.join(flutterPath, "bin", flutterExecutable);

  if (!File(flutterBinPath).existsSync()) {
    print("Flutter executable not found at path: $flutterBinPath");
    exit(1);
  }

  final buildCommand = [
    flutterBinPath,
    "build",
    platform,
    "--dart-define",
    "FLUTTER_BUILD_NAME=$buildName",
    "--dart-define",
    "FLUTTER_BUILD_NUMBER=$buildNumber",
  ];

  print("Executing build command: ${buildCommand.join(' ')}");

  // Replace Process.run with Process.start to handle real-time output
  final process = await Process.start(buildCommand.first, buildCommand.sublist(1));

  process.stdout.transform(utf8.decoder).listen(print);
  process.stderr.transform(utf8.decoder).listen((data) {
    stderr.writeln(data);
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.writeln("Build failed with exit code $exitCode");
    exit(1);
  }

  print("Build completed successfully");

  late Directory buildDir;

  // Determine the build directory based on the platform
  if (platform == "windows") {
    buildDir = Directory(
      path.join("build", "windows", "x64", "runner", "Release"),
    );
  } else if (platform == "macos") {
    buildDir = Directory(
      path.join(
        "build",
        "macos",
        "Build",
        "Products",
        "Release"
      )
    );
    var appBundle = (await findFirstAppBundle(buildDir.path));
    if (appBundle != null) {
      buildDir = Directory(appBundle.path);
    } else {
      buildDir = Directory(path.join(buildDir.path, appNamePubspec));
    }
  } else if (platform == "linux") {
    buildDir = Directory(
      path.join("build", "linux", "x64", "release", "bundle"),
    );
  }

  if (!buildDir.existsSync()) {
    print("Build directory not found: ${buildDir.path}");
    exit(1);
  }

  final distPath = platform == "windows"
      ? path.join(
          "dist",
          "updater",
          "staged",
          buildName,
          "$platform-bundle",
        )
      : platform == "macos"
          ? path.join(
              "dist",
              "updater",
              "staged",
              buildName,
              "$platform-bundle",
            )
          : path.join(
              "dist",
              "updater",
              "staged",
              buildName,
              "$platform-bundle",
            );

  final distDir = Directory(distPath);
  if (distDir.existsSync()) {
    distDir.deleteSync(recursive: true);
  }

  // Copy buildDir to distPath
  await copyDirectory(buildDir, Directory(distPath));

  print("Archive created at $distPath");
}

// Helper function to copy directories recursively
Future<void> copyDirectory(Directory source, Directory destination) async {
  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }

  await for (final entity in source.list(recursive: false, followLinks: false)) {
    final newPath = path.join(destination.path, path.basename(entity.path));

    if (entity is Link) {
      final target = await entity.target();
      await Link(newPath).create(target, recursive: true);
    } else if (entity is File) {
      await File(entity.path).copy(newPath);
    } else if (entity is Directory) {
      await copyDirectory(entity, Directory(newPath));
    }
  }
}

/// Finds the first `.app` bundle in the specified directory.
/// Returns null if not found.
Future<FileSystemEntity?> findFirstAppBundle(String directoryPath) async {
  final dir = Directory(directoryPath);

  if (!await dir.exists()) return null;

  return dir
      .list()
      .firstWhere(
        (entity) => entity.path.endsWith(".app"),
      );
}
