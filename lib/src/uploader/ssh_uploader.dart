import "dart:io";
import "package:dartssh2/dartssh2.dart";
import "package:path/path.dart" as path;
import "package:yaml/yaml.dart";

Future<void> uploadViaSSH(
  YamlMap config,
  String version,
  String platformStr,
  Directory localDir,
  bool shouldRetry,
) async {
  final host = config['host']?.toString();
  final port = int.tryParse(config['port'].toString()) ?? 22;
  final username = config['username']?.toString();
  final password = config['password']?.toString();

  if ([host, port, username, password].contains(null)) {
    print('Missing SSH config values');
    return;
  }

  final socket = await SSHSocket.connect(host!, port);
  final client = SSHClient(
    socket,
    username: username!,
    onPasswordRequest: () => password!,
  );

  final sftp = await client.sftp();
  final remoteBasePath = '$version/${platformStr}-bundle';

  try {
    if (!shouldRetry) {
      final stat = await _safeStat(sftp, remoteBasePath);
      if (stat != null) {
        print('❌ Version "$version" has already been released for $platformStr. Please bump the version first.');
        client.close();
        return;
      }
    }

    await _mkdirRecursive(sftp, remoteBasePath);

    final files = await localDir.list(recursive: true).where((f) => f is File).cast<File>().toList();
    bool uploadFailed = false;

    for (final file in files) {
      final relativePath = path.relative(file.path, from: localDir.path);
      final remotePath = path.join(remoteBasePath, relativePath).replaceAll('\\', '/');

      try {
        final remoteDir = path.dirname(remotePath).replaceAll('\\', '/');
        await _mkdirRecursive(sftp, remoteDir);
        final remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
        final localBytesStream = file.readAsBytes().asStream();
        await remoteFile.write(localBytesStream);
        await remoteFile.close();
        print('Uploaded: $relativePath');
      } catch (e) {
        print('❌ Failed to upload: $relativePath → $e');
        uploadFailed = true;
      }
    }

    client.close();

    final failedFlag = File('.failed_upload');
    if (uploadFailed) {
      await failedFlag.writeAsString('Upload failed for $version on $platformStr');
      print('⚠️ Some files failed to upload. A .failed_upload flag has been created.');
    } else {
      if (await failedFlag.exists()) await failedFlag.delete();
      print('✅ Upload complete.');
    }
  } catch (e) {
    await File('.failed_upload').writeAsString('Upload failed: $e');
    print('❌ SSH upload failed: $e');
    client.close();
  }
}

Future<void> _mkdirRecursive(SftpClient sftp, String dir) async {
  final parts = path.posix.split(dir);
  String current = '.';
  for (final part in parts) {
    current = path.posix.join(current, part);
    try {
      await sftp.stat(current);
    } catch (_) {
      try {
        await sftp.mkdir(current);
      } catch (_) {}
    }
  }
}

Future<SftpFileAttrs?> _safeStat(SftpClient sftp, String path) async {
  try {
    return await sftp.stat(path);
  } catch (_) {
    return null;
  }
}
