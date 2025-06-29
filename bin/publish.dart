import "dart:io";

import "package:desktop_updater/src/uploader/ssh_uploader.dart";
import "package:pubspec_parse/pubspec_parse.dart";
import "package:yaml/yaml.dart";
import "helper/bootstrap_config.dart";

Future<void> main(List<String> args) async {
  final configFile = File("automatic_updates.yaml");
  if (!await configFile.exists()) {
    await createDefaultConfig();
    print('No configuration found. Created default automatic_updates.yaml');
    return;
  }

  final yamlContent = loadYaml(await configFile.readAsString()) as YamlMap;
  final method = yamlContent.keys.firstWhere(
    (key) => yamlContent[key] != null && yamlContent[key] is YamlMap,
    orElse: () => 'git',
  );

  final config = yamlContent[method] as YamlMap;

  final pubspecContent = await File('pubspec.yaml').readAsString();
  final pubspec = Pubspec.parse(pubspecContent);
  final version = pubspec.version?.toString();

  if (version == null) {
    print('Could not find version in pubspec.yaml');
    return;
  }

  final platformStr = Platform.operatingSystem;
  final localDir = Directory('dist/updater/release/$version/${platformStr}-bundle');
  if (!await localDir.exists()) {
    print('Directory not found: ${localDir.path}');
    return;
  }

  final failedFlag = File(".failed_upload");
  bool shouldRetry = false;

  if (await failedFlag.exists()) {
    stdout.write("⚠️ Previous upload attempt detected. Replace existing remote files? (y/N): ");
    final response = stdin.readLineSync()?.toLowerCase().trim();
    if (response != "y") {
      print("Aborting upload.");
      return;
    }
    shouldRetry = true;
  }

  switch (method) {
    case "ssh":
      await uploadViaSSH(config, version, platformStr, localDir, shouldRetry);
      break;
    default:
      print('Uploader for "$method" not implemented yet.');
      break;
  }
}
