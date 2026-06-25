import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;

class AdminAssetRef {
  final String label;
  final String pathOrUrl;

  const AdminAssetRef({required this.label, required this.pathOrUrl});
}

Map<String, dynamic>? parseJsonMap(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {}
  return null;
}

dynamic parseJsonDynamic(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

List<AdminAssetRef> extractAdminAssetRefs(String raw) {
  final out = <AdminAssetRef>[];
  final parsed = parseJsonMap(raw);
  if (parsed == null) return out;

  void walk(String prefix, dynamic node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key.toString();
        final nextPrefix = prefix.isEmpty ? key : '$prefix > $key';
        walk(nextPrefix, entry.value);
      }
      return;
    }
    if (node is List) {
      for (final value in node) {
        walk(prefix, value);
      }
      return;
    }
    if (node is String) {
      final value = node.trim();
      if (value.isEmpty) return;
      final lower = value.toLowerCase();
      final looksLikeFile = lower.startsWith('http://') ||
          lower.startsWith('https://') ||
          lower.startsWith('content://') ||
          lower.startsWith('/') ||
          lower.contains(':\\') ||
          lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.heic') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.pdf');
      if (!looksLikeFile) return;
      out.add(AdminAssetRef(label: prefix, pathOrUrl: value));
    }
  }

  walk('', parsed);
  return out;
}

bool isAdminAssetImage(String pathOrUrl) {
  final v = pathOrUrl.toLowerCase();
  return v.endsWith('.png') ||
      v.endsWith('.jpg') ||
      v.endsWith('.jpeg') ||
      v.endsWith('.webp') ||
      v.endsWith('.gif') ||
      v.endsWith('.heic');
}

bool isAdminAssetPdf(String pathOrUrl) {
  return pathOrUrl.toLowerCase().endsWith('.pdf');
}

String adminAssetBasename(String pathOrUrl) {
  if (pathOrUrl.startsWith('content://')) {
    final u = Uri.tryParse(pathOrUrl);
    if (u != null && u.pathSegments.isNotEmpty) {
      return u.pathSegments.last;
    }
    return 'document';
  }
  final normalized = pathOrUrl.replaceAll('\\', '/');
  final idx = normalized.lastIndexOf('/');
  if (idx < 0 || idx + 1 >= normalized.length) return normalized;
  final name = normalized.substring(idx + 1);
  return name.split('?').first;
}

String adminAssetSafeFileName(String input) {
  final raw = input.trim().isEmpty ? 'document' : input.trim();
  final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  return cleaned.isEmpty ? 'document' : cleaned;
}

Future<void> previewAdminAsset(BuildContext context, AdminAssetRef asset) async {
  if (isAdminAssetImage(asset.pathOrUrl)) {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: asset.pathOrUrl.startsWith('http://') ||
                  asset.pathOrUrl.startsWith('https://')
              ? Image.network(asset.pathOrUrl, fit: BoxFit.contain)
              : Image.file(File(asset.pathOrUrl), fit: BoxFit.contain),
        ),
      ),
    );
    return;
  }

  if (isAdminAssetPdf(asset.pathOrUrl)) {
    try {
      String filePath = asset.pathOrUrl;
      if (asset.pathOrUrl.startsWith('http://') ||
          asset.pathOrUrl.startsWith('https://')) {
        final res = await http.get(Uri.parse(asset.pathOrUrl));
        if (res.statusCode >= 400) {
          throw Exception('Failed to fetch PDF (${res.statusCode})');
        }
        final tmp = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_${adminAssetBasename(asset.pathOrUrl)}',
        );
        await tmp.writeAsBytes(res.bodyBytes, flush: true);
        filePath = tmp.path;
      } else if (asset.pathOrUrl.startsWith('content://')) {
        throw Exception('Download the PDF first to open it.');
      } else {
        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception('PDF file not found');
        }
      }
      // ✅ mounted check avant usage de context après les awaits
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 700,
            height: 720,
            child: PDFView(filePath: filePath),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
    return;
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Preview for this file type is not supported. Use Download.')),
  );
}

Future<void> downloadAdminAsset(BuildContext context, AdminAssetRef asset) async {
  try {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing download...')),
      );
    }
    final name = adminAssetSafeFileName(adminAssetBasename(asset.pathOrUrl));
    late final List<int> bytes;
    if (asset.pathOrUrl.startsWith('http://') ||
        asset.pathOrUrl.startsWith('https://')) {
      final res = await http.get(Uri.parse(asset.pathOrUrl));
      if (res.statusCode >= 400) {
        throw Exception('Failed to download (${res.statusCode})');
      }
      bytes = res.bodyBytes;
    } else if (asset.pathOrUrl.startsWith('content://')) {
      final saved = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: asset.pathOrUrl,
          fileName: name,
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              saved == null ? 'Download canceled' : 'Downloaded: $saved'),
        ),
      );
      return;
    } else {
      final file = File(asset.pathOrUrl);
      if (!await file.exists()) {
        throw Exception('File not found on this device');
      }
      bytes = await file.readAsBytes();
    }
    final savedPath = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: Uint8List.fromList(bytes),
        fileName: name,
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(savedPath == null
            ? 'Download canceled'
            : 'Downloaded: $savedPath'),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}