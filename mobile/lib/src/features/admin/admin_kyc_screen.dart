import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class AdminKYCScreen extends StatefulWidget {
  const AdminKYCScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<AdminKYCScreen> createState() => _AdminKYCScreenState();
}

class _AdminKYCScreenState extends State<AdminKYCScreen> {
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
      _items = await widget.api.adminKYC();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _parseJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  List<_KycAssetRef> _extractAssetRefs(String raw) {
    final out = <_KycAssetRef>[];
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
        out.add(_KycAssetRef(label: prefix, pathOrUrl: value));
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

  bool _isPdf(String pathOrUrl) {
    return pathOrUrl.toLowerCase().endsWith('.pdf');
  }

  List<MapEntry<String, String>> _flattenMap(Map<String, dynamic> map, [String prefix = '']) {
    final out = <MapEntry<String, String>>[];
    for (final entry in map.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix > ${entry.key}';
      final value = entry.value;
      if (value is Map) {
        out.addAll(_flattenMap(value.cast<String, dynamic>(), key));
        continue;
      }
      if (value is List) {
        out.add(MapEntry<String, String>(key, value.join(', ')));
        continue;
      }
      out.add(MapEntry<String, String>(key, value?.toString() ?? ''));
    }
    return out;
  }

  Widget _friendlyMapView(Map<String, dynamic> map) {
    final rows = _flattenMap(map);
    if (rows.isEmpty) {
      return const Text('No structured details available');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      r.key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 6, child: Text(r.value)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  String _basename(String pathOrUrl) {
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

  String _safeFileName(String input) {
    final raw = input.trim().isEmpty ? 'document' : input.trim();
    final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (cleaned.isEmpty) return 'document';
    return cleaned;
  }

  Future<void> _previewAsset(_KycAssetRef asset) async {
    if (_isImage(asset.pathOrUrl)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: asset.pathOrUrl.startsWith('http://') || asset.pathOrUrl.startsWith('https://')
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
        if (asset.pathOrUrl.startsWith('http://') || asset.pathOrUrl.startsWith('https://')) {
          final res = await http.get(Uri.parse(asset.pathOrUrl));
          if (res.statusCode >= 400) {
            throw Exception('Failed to fetch PDF (${res.statusCode})');
          }
          final tmp = File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_${_basename(asset.pathOrUrl)}',
          );
          await tmp.writeAsBytes(res.bodyBytes, flush: true);
          filePath = tmp.path;
        } else {
          final f = File(filePath);
          if (!await f.exists()) throw Exception('PDF file not found');
        }
        if (!mounted) return;
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preview for this file type is not supported. Use Download.')),
    );
  }

  Future<void> _downloadAsset(_KycAssetRef asset) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing download...')),
        );
      }
      final name = _safeFileName(_basename(asset.pathOrUrl));
      late final List<int> bytes;
      String? savedPath;
      if (asset.pathOrUrl.startsWith('http://') || asset.pathOrUrl.startsWith('https://')) {
        final res = await http.get(Uri.parse(asset.pathOrUrl));
        if (res.statusCode >= 400) {
          throw Exception('Failed to download file (${res.statusCode})');
        }
        bytes = res.bodyBytes;
      } else if (asset.pathOrUrl.startsWith('content://')) {
        savedPath = await FlutterFileDialog.saveFile(
          params: SaveFileDialogParams(
            sourceFilePath: asset.pathOrUrl,
            fileName: name,
          ),
        );
        if (savedPath == null) {
          throw Exception('Download canceled');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded: $savedPath')),
        );
        return;
      } else {
        // Local path. If it does not exist on this device, admin cannot download it.
        final file = File(asset.pathOrUrl);
        if (!await file.exists()) {
          throw Exception('File not found on device');
        }
        bytes = await file.readAsBytes();
      }
      savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          data: Uint8List.fromList(bytes),
          fileName: name,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath == null
                ? 'Download canceled'
                : 'Downloaded: $savedPath',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openReview(Map<String, dynamic> item) async {
    final notesCtrl =
        TextEditingController(text: (item['review_notes'] as String?) ?? '');
    String selected =
        (item['status'] as String?) == 'verified' ? 'verified' : 'rejected';
    final docRef = (item['document_reference'] as String?) ?? '';
    final addressRef = (item['address_proof_ref'] as String?) ?? '';
    final docMap = _parseJsonMap(docRef);
    final addrMap = _parseJsonMap(addressRef);
    final assetRefs = _extractAssetRefs(docRef);

    if (!mounted) return;
    final result = await showDialog<_KycReviewDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('KYC Request Details'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('User ID: ${item['user_id']}'),
                Text('Status: ${item['status']}'),
                Text('Document Type: ${item['document_type']}'),
                const SizedBox(height: 10),
                const Text('Uploaded Evidence', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (assetRefs.isNotEmpty) ...[
                  ...assetRefs.map((asset) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(_isPdf(asset.pathOrUrl)
                                      ? Icons.picture_as_pdf
                                      : Icons.image),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      asset.label.isEmpty
                                          ? 'Uploaded File'
                                          : asset.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(_basename(asset.pathOrUrl)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _previewAsset(asset),
                                    icon: const Icon(Icons.remove_red_eye),
                                    label: Text(_isPdf(asset.pathOrUrl)
                                        ? 'Open'
                                        : 'Preview'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => _downloadAsset(asset),
                                    icon: const Icon(Icons.download),
                                    label: const Text('Download'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                ] else if (docMap != null) ...[
                  _friendlyMapView(docMap),
                ] else ...[
                  SelectableText(docRef),
                ],
                const SizedBox(height: 8),
                const Text('Address/Home Data', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (addrMap != null) ...[
                  _friendlyMapView(addrMap),
                ] else ...[
                  SelectableText(addressRef),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  items: const [
                    DropdownMenuItem(value: 'verified', child: Text('Verify')),
                    DropdownMenuItem(value: 'rejected', child: Text('Reject')),
                  ],
                  onChanged: (v) => selected = v ?? 'rejected',
                  decoration: const InputDecoration(labelText: 'Decision'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reason / Notes (sent to user notification)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(const _KycReviewDecision(
              confirmed: false,
              status: '',
              notes: '',
            )),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              _KycReviewDecision(
                confirmed: true,
                status: selected,
                notes: notesCtrl.text.trim(),
              ),
            ),
            child: const Text('Submit Review'),
          ),
        ],
      ),
    );

    notesCtrl.dispose();
    if (result == null || !result.confirmed) {
      return;
    }
    if (result.status == 'rejected' && result.notes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a rejection reason')),
      );
      return;
    }
    try {
      if (!mounted) return;
      await widget.api.adminReviewKYC(
        id: (item['id'] as String?) ?? '',
        status: result.status,
        notes: result.notes,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KYC review saved and user notified')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
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
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const Text('KYC Review Queue', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._items.map((e) {
              final item = (e as Map).cast<String, dynamic>();
              return Card(
                child: ListTile(
                  onTap: () => _openReview(item),
                  title: Text('User ${item['user_id']} | ${item['status']}'),
                  subtitle: Text('Doc: ${item['document_type']}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _KycAssetRef {
  const _KycAssetRef({required this.label, required this.pathOrUrl});
  final String label;
  final String pathOrUrl;
}

class _KycReviewDecision {
  const _KycReviewDecision({
    required this.confirmed,
    required this.status,
    required this.notes,
  });

  final bool confirmed;
  final String status;
  final String notes;
}
