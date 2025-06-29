import "dart:io";

Future<void> createDefaultConfig() async {
  final file = File("automatic_updates.yaml");
  if (await file.exists()) return;

  await file.writeAsString("""
# automatic_updates.yaml

# Default upload method
ssh:
  host: your.server.com
  port: 22
  username: your-username
  password: your-password
  # OR use: key_file: /path/to/private.key

# Available (but inactive) methods
# rsync: {}
# scp: {}
# s3: {}
# ftp: {}
# git: {}
""");
}