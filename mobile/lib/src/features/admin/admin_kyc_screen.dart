import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';
import 'admin_asset_helper.dart';

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

  Map<String, dynamic>? _parseJsonMap(String value) => parseJsonMap(value);

  List<AdminAssetRef> _extractAssetRefs(String raw) => extractAdminAssetRefs(raw);

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
    final entries = _flattenMap(map);
    if (entries.isEmpty) {
      return const Text('Aucune donnée disponible.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 170,
                child: Text(
                  e.key,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Text(e.value.isEmpty ? '-' : e.value),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _previewAsset(AdminAssetRef asset) async {
    await previewAdminAsset(context, asset);
  }

  Future<void> _downloadAsset(AdminAssetRef asset) async {
    await downloadAdminAsset(context, asset);
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
                                  Icon(isAdminAssetPdf(asset.pathOrUrl)
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
                              Text(adminAssetBasename(asset.pathOrUrl)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _previewAsset(asset),
                                    icon: const Icon(Icons.remove_red_eye),
                                    label: Text(isAdminAssetPdf(asset.pathOrUrl)
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