import 'dart:io';
import 'dart:typed_data';

Future<String> saveBytes(String filename, Uint8List bytes, {String mime = 'application/octet-stream'}) async {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  final dir = Directory('$home${Platform.pathSeparator}Downloads');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes);
  return file.path;
}
