import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class AdminPackagesScreen extends StatefulWidget {
  const AdminPackagesScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<AdminPackagesScreen> createState() => _AdminPackagesScreenState();
}

class _AdminPackagesScreenState extends State<AdminPackagesScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _items = await widget.api.adminPackageVerifications();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(String id, String status, {String notes = ''}) async {
    try {
      await widget.api.adminReviewPackage(id: id, status: status, notes: notes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved'
                  ? 'Request approved and client notified.'
                  : 'Request disapproved and client notified.',
            ),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _openReviewActionDialog({
    required String verificationID,
    required String status,
  }) async {
    final reasonCtrl = TextEditingController();
    final isDisapprove = status != 'approved';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isDisapprove ? 'Disapprove Request' : 'Approve Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isDisapprove
                  ? 'Add reason to notify the client why this was disapproved.'
                  : 'Add optional note for the client (recommended).',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText:
                    isDisapprove ? 'Reason (required)' : 'Note (optional)',
                hintText: isDisapprove
                    ? 'Example: Receipt is unclear, please upload a readable one.'
                    : 'Example: Verification passed, package is cleared.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (isDisapprove && reasonCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Reason is required to disapprove.')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: Text(isDisapprove ? 'Disapprove' : 'Approve'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _review(
        verificationID,
        status,
        notes: reasonCtrl.text.trim(),
      );
    }
  }

  Map<String, dynamic>? _parseJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  dynamic _parseJsonDynamic(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  List<_PkgAssetRef> _extractAssetRefs(String raw) {
    final out = <_PkgAssetRef>[];
    final parsed = _parseJsonMap(raw);
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
        for (final v in node) {
          walk(prefix, v);
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
            lower.endsWith('.webp') ||
            lower.endsWith('.gif') ||
            lower.endsWith('.heic') ||
            lower.endsWith('.pdf');
        if (!looksLikeFile) return;
        out.add(_PkgAssetRef(label: prefix, pathOrUrl: value));
      }
    }

    walk('', parsed);
    return out;
  }

  bool _isImage(String pathOrUrl) {
    final v = pathOrUrl.toLowerCase();
    return v.endsWith('.png') ||
        v.endsWith('.jpg') ||
        v.endsWith('.jpeg') ||
        v.endsWith('.webp') ||
        v.endsWith('.gif') ||
        v.endsWith('.heic');
  }

  bool _isPdf(String pathOrUrl) => pathOrUrl.toLowerCase().endsWith('.pdf');

  String _basename(String pathOrUrl) {
    if (pathOrUrl.startsWith('content://')) {
      final u = Uri.tryParse(pathOrUrl);
      if (u != null && u.pathSegments.isNotEmpty) return u.pathSegments.last;
      return 'document';
    }
    final normalized = pathOrUrl.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    if (idx < 0 || idx + 1 >= normalized.length) return normalized;
    return normalized.substring(idx + 1).split('?').first;
  }

  String _safeFileName(String input) {
    final raw = input.trim().isEmpty ? 'document' : input.trim();
    final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '_');
    return cleaned.isEmpty ? 'document' : cleaned;
  }

  Future<void> _previewAsset(_PkgAssetRef asset) async {
    if (_isImage(asset.pathOrUrl)) {
      if (!mounted) return;
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
    if (_isPdf(asset.pathOrUrl)) {
      try {
        String filePath = asset.pathOrUrl;
        if (asset.pathOrUrl.startsWith('http://') ||
            asset.pathOrUrl.startsWith('https://')) {
          final res = await http.get(Uri.parse(asset.pathOrUrl));
          if (res.statusCode >= 400) {
            throw Exception('Failed to fetch PDF (${res.statusCode})');
          }
          final tmp = File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_${_basename(asset.pathOrUrl)}',
          );
          await tmp.writeAsBytes(res.bodyBytes, flush: true);
          filePath = tmp.path;
        } else if (asset.pathOrUrl.startsWith('content://')) {
          // Can't preview content:// reliably here; download first.
          throw Exception('Download the PDF first to open it.');
        } else {
          if (!await File(filePath).exists()) {
            throw Exception('PDF file not found');
          }
        }
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: SizedBox(
                width: 700, height: 720, child: PDFView(filePath: filePath)),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Preview not supported for this file type.')),
    );
  }

  Future<void> _downloadAsset(_PkgAssetRef asset) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing download...')),
        );
      }
      final name = _safeFileName(_basename(asset.pathOrUrl));
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
              sourceFilePath: asset.pathOrUrl, fileName: name),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  saved == null ? 'Download canceled' : 'Downloaded: $saved')),
        );
        return;
      } else {
        final f = File(asset.pathOrUrl);
        if (!await f.exists()) throw Exception('File not found on this device');
        bytes = await f.readAsBytes();
      }
      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
            data: Uint8List.fromList(bytes), fileName: name),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(savedPath == null
                ? 'Download canceled'
                : 'Downloaded: $savedPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openDetails(Map<String, dynamic> item) async {
    final receiptRef = (item['receipt_ref'] as String?) ?? '';
    final parsed = _parseJsonMap(receiptRef);
    final assets = _extractAssetRefs(receiptRef);
    final category = (parsed?['category'] ?? '').toString().trim();
    final screeningMethod = (item['screening_method'] ?? '').toString().trim();
    final reviewNotes = (item['review_notes'] ?? '').toString().trim();
    final createdAt = _formatDate(item['created_at']?.toString());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Package Review Details'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Request ${item['request_id'] ?? ''}')),
                    Chip(label: Text('Status ${item['status'] ?? ''}')),
                    Chip(label: Text('Risk ${item['risk_score'] ?? '-'}')),
                    if (category.isNotEmpty)
                      Chip(label: Text('Category $category')),
                  ],
                ),
                const SizedBox(height: 8),
                if (createdAt.isNotEmpty) Text('Submitted: $createdAt'),
                if (screeningMethod.isNotEmpty)
                  Text('Screening: $screeningMethod'),
                const SizedBox(height: 12),
                if (((item['declared_contents'] ?? '').toString().trim())
                    .isNotEmpty) ...[
                  const Text('Declared Contents',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  ..._buildDeclaredContents(
                      (item['declared_contents'] ?? '').toString()),
                  const SizedBox(height: 12),
                ],
                const Text('Attached Files',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (assets.isNotEmpty) ...[
                  ...assets.map((a) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.label.isEmpty ? 'File' : a.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(_basename(a.pathOrUrl)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _previewAsset(a),
                                    icon: const Icon(Icons.remove_red_eye),
                                    label: Text(_isPdf(a.pathOrUrl)
                                        ? 'Open'
                                        : 'Preview'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => _downloadAsset(a),
                                    icon: const Icon(Icons.download),
                                    label: const Text('Download'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                ] else ...[
                  const Text('No files were attached for this request.'),
                ],
                const SizedBox(height: 12),
                const Text('Submission Details',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ..._buildSubmissionDetails(parsed),
                if (reviewNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Admin Notes',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(reviewNotes),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () => _openReviewActionDialog(
              verificationID: (item['id'] ?? '').toString(),
              status: 'approved',
            ),
            icon: const Icon(Icons.verified),
            label: const Text('Approve'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _openReviewActionDialog(
              verificationID: (item['id'] ?? '').toString(),
              status: 'rejected',
            ),
            icon: const Icon(Icons.gpp_bad),
            label: const Text('Disapprove'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSubmissionDetails(Map<String, dynamic>? parsed) {
    if (parsed == null || parsed.isEmpty) {
      return const [Text('No structured details available.')];
    }
    final widgets = <Widget>[];
    final skipKeys = {'receipt', 'attachments'};
    parsed.forEach((key, value) {
      if (skipKeys.contains(key)) return;
      if (value == null) return;
      if (value is String) {
        final asJson = _parseJsonDynamic(value);
        if (asJson is Map || asJson is List) {
          value = asJson;
        }
      }
      final label = _friendlyLabel(key);
      if (value is Map) {
        final mapValue = value.cast<dynamic, dynamic>();
        if (mapValue.isEmpty) return;
        widgets.add(
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        );
        widgets.add(const SizedBox(height: 4));
        mapValue.forEach((k, v) {
          widgets.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 170,
                  child: Text(
                    _friendlyLabel(k.toString()),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(child: Text(_friendlyValue(v))),
              ],
            ),
          );
          widgets.add(const SizedBox(height: 6));
        });
        widgets.add(const SizedBox(height: 6));
        return;
      }
      if (value is List) {
        if (value.isEmpty) return;
        final values = value
            .map(_friendlyValue)
            .where((e) => e.trim().isNotEmpty)
            .toList();
        if (values.isEmpty) return;
        widgets.add(
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)));
        widgets.add(const SizedBox(height: 4));
        widgets.add(Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values.map((v) => Chip(label: Text(v))).toList()));
        widgets.add(const SizedBox(height: 8));
        return;
      }
      widgets.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 170,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(_friendlyValue(value))),
        ],
      ));
      widgets.add(const SizedBox(height: 8));
    });
    if (widgets.isEmpty) {
      return const [Text('No structured details available.')];
    }
    return widgets;
  }

  String _friendlyLabel(String key) {
    final cleaned = key.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return key;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  String _friendlyValue(dynamic value) {
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is Map) {
      final pairs = value.entries.map((e) =>
          '${_friendlyLabel(e.key.toString())}: ${_friendlyValue(e.value)}');
      return pairs.join(', ');
    }
    if (value is List) {
      return value.map(_friendlyValue).join(', ');
    }
    return value.toString();
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.toLocal()}'.split('.').first;
  }

  List<Widget> _buildDeclaredContents(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const [Text('Not provided')];
    final parsed = _parseJsonDynamic(value);
    if (parsed is Map) {
      final rows = <Widget>[];
      parsed.forEach((k, v) {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Text(
                _friendlyLabel(k.toString()),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(_friendlyValue(v))),
          ],
        ));
        rows.add(const SizedBox(height: 6));
      });
      return rows.isEmpty ? const [Text('Not provided')] : rows;
    }
    if (parsed is List) {
      final values =
          parsed.map(_friendlyValue).where((e) => e.trim().isNotEmpty).toList();
      if (values.isNotEmpty) {
        return [
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: values.map((v) => Chip(label: Text(v))).toList())
        ];
      }
    }
    return [Text(raw)];
  }

  String _briefContents(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return 'No description';
    final parsed = _parseJsonDynamic(text);
    if (parsed is Map) {
      final keys =
          parsed.keys.map((e) => _friendlyLabel(e.toString())).toList();
      return keys.isEmpty ? 'Submitted details' : keys.take(2).join(' | ');
    }
    if (parsed is List) {
      final values =
          parsed.map(_friendlyValue).where((e) => e.trim().isNotEmpty).toList();
      if (values.isNotEmpty) return values.take(2).join(' | ');
    }
    return text.length > 64 ? '${text.substring(0, 64)}...' : text;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const Text('Package Review Queue',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ..._items.map((e) {
              final item = (e as Map).cast<String, dynamic>();
              return Card(
                child: ListTile(
                  onTap: () => _openDetails(item),
                  title: Text('Req ${item['request_id']} | ${item['status']}'),
                  subtitle: Text(
                      'Risk ${item['risk_score']} | ${_briefContents(item['declared_contents'])}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _openDetails(item),
                        icon: const Icon(Icons.rate_review),
                        label: const Text('Review'),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _PkgAssetRef {
  const _PkgAssetRef({required this.label, required this.pathOrUrl});
  final String label;
  final String pathOrUrl;
}
