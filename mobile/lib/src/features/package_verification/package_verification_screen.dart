import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class PackageVerificationScreen extends StatefulWidget {
  const PackageVerificationScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<PackageVerificationScreen> createState() => _PackageVerificationScreenState();
}

class _PackageVerificationScreenState extends State<PackageVerificationScreen> {
  final _picker = ImagePicker();
  String _selectedRequestId = '';
  final _contents = TextEditingController(text: 'Electronics accessories');
  final _receiptRef = TextEditingController();
  final _method = TextEditingController(text: 'document_and_photo');
  final _risk = TextEditingController(text: '20');
  List<dynamic> _items = [];
  List<dynamic> _myRequests = [];
  String? _error;
  bool _loading = false;

  String _category = 'electronics';
  bool _hasBattery = false;
  bool _hasLiquid = false;
  bool _hasMedicine = false;
  bool _attest = false;

  String _receiptPath = '';
  final List<String> _attachments = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contents.dispose();
    _receiptRef.dispose();
    _method.dispose();
    _risk.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _myRequests = await widget.api.myRequests();
      if (_selectedRequestId.isEmpty && _myRequests.isNotEmpty) {
        _selectedRequestId = (_myRequests.first['id'] as String?) ?? '';
      }
      _items = await widget.api.myPackageVerifications();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseReceipt() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take receipt photo'),
              onTap: () async {
                Navigator.pop(context);
                final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                if (file == null || !mounted) return;
                setState(() => _receiptPath = file.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pick receipt image'),
              onTap: () async {
                Navigator.pop(context);
                final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (file == null || !mounted) return;
                setState(() => _receiptPath = file.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Pick receipt PDF'),
              onTap: () async {
                Navigator.pop(context);
                final res = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['pdf'],
                );
                if (res == null || res.files.isEmpty) return;
                final path = res.files.first.path ?? '';
                if (path.isEmpty || !mounted) return;
                setState(() => _receiptPath = path);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAttachment() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take package photo'),
              onTap: () async {
                Navigator.pop(context);
                final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                if (file == null || !mounted) return;
                setState(() => _attachments.add(file.path));
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pick image'),
              onTap: () async {
                Navigator.pop(context);
                final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (file == null || !mounted) return;
                setState(() => _attachments.add(file.path));
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Pick PDF'),
              onTap: () async {
                Navigator.pop(context);
                final res = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['pdf'],
                );
                if (res == null || res.files.isEmpty) return;
                final path = res.files.first.path ?? '';
                if (path.isEmpty || !mounted) return;
                setState(() => _attachments.add(path));
              },
            ),
          ],
        ),
      ),
    );
  }

  String _short(String value) {
    if (value.isEmpty) return 'Not selected';
    final normalized = value.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    final name = idx >= 0 ? normalized.substring(idx + 1) : normalized;
    return name.isEmpty ? value : name;
  }

  Future<void> _submit() async {
    try {
      if (_selectedRequestId.trim().isEmpty) {
        throw Exception('Select a request first');
      }
      if (_contents.text.trim().isEmpty) {
        throw Exception('Declared contents is required');
      }
      if (_receiptPath.trim().isEmpty) {
        throw Exception('Upload a receipt/invoice (image or PDF) first');
      }
      if (!_attest) {
        throw Exception('You must confirm the safety declaration');
      }

      final receiptPayload = <String, dynamic>{
        'receipt': _receiptPath.trim(),
        'attachments': _attachments,
        'category': _category,
        'danger_flags': {
          'battery': _hasBattery,
          'liquid': _hasLiquid,
          'medicine': _hasMedicine,
        },
        'attested': _attest,
        'created_at': DateTime.now().toIso8601String(),
      };
      await widget.api.submitPackageVerification(
        requestID: _selectedRequestId.trim(),
        declaredContents: _contents.text.trim(),
        receiptRef: jsonEncode(receiptPayload),
        screeningMethod: _method.text.trim(),
        riskScore: int.tryParse(_risk.text) ?? 0,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = widget.api.role == 'client' || widget.api.role == 'admin';
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          const Text('Package Safety Submission', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (!canSubmit) ...[
            const Text('Package verification is submitted by client accounts.'),
          ] else if (_myRequests.isEmpty) ...[
            const Text('Create a delivery request first, then come back here to submit package verification.'),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedRequestId.isEmpty ? null : _selectedRequestId,
              items: _myRequests
                  .map((r) => DropdownMenuItem<String>(
                        value: (r['id'] as String?) ?? '',
                        child: Text('${r['origin']} -> ${r['destination']}  (id: ${r['id']})'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedRequestId = v ?? ''),
              decoration: const InputDecoration(labelText: 'Select Your Request'),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _contents,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Declared Contents (be specific)',
              hintText: 'e.g. 2x phone cases, 1x charger, 1x screen protector',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _category,
            items: const [
              DropdownMenuItem(value: 'electronics', child: Text('Electronics')),
              DropdownMenuItem(value: 'clothing', child: Text('Clothing')),
              DropdownMenuItem(value: 'documents', child: Text('Documents')),
              DropdownMenuItem(value: 'cosmetics', child: Text('Cosmetics')),
              DropdownMenuItem(value: 'food', child: Text('Food')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _category = v ?? 'other'),
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Receipt / Invoice (required)'),
              subtitle: Text(_short(_receiptPath)),
              trailing: OutlinedButton(
                onPressed: canSubmit && _myRequests.isNotEmpty ? _chooseReceipt : null,
                child: const Text('Upload'),
              ),
            ),
          ),
          if (_receiptPath.isNotEmpty && File(_receiptPath).existsSync() && _receiptPath.toLowerCase().endsWith('.pdf') == false)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_receiptPath),
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Additional Evidence (optional)'),
                  subtitle: Text(_attachments.isEmpty ? 'No attachments' : '${_attachments.length} file(s)'),
                  trailing: OutlinedButton(
                    onPressed: canSubmit && _myRequests.isNotEmpty ? _addAttachment : null,
                    child: const Text('Add'),
                  ),
                ),
                if (_attachments.isNotEmpty)
                  ..._attachments.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final path = entry.value;
                    return ListTile(
                      dense: true,
                      leading: Icon(path.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image),
                      title: Text(_short(path)),
                      trailing: IconButton(
                        onPressed: () => setState(() => _attachments.removeAt(idx)),
                        icon: const Icon(Icons.close),
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _method.text.trim().isEmpty ? 'document_and_photo' : _method.text.trim(),
            items: const [
              DropdownMenuItem(value: 'document_only', child: Text('Document only')),
              DropdownMenuItem(value: 'document_and_photo', child: Text('Document + photos')),
              DropdownMenuItem(value: 'manual_review', child: Text('Manual review')),
            ],
            onChanged: (v) => setState(() => _method.text = v ?? 'document_and_photo'),
            decoration: const InputDecoration(labelText: 'Screening Method'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _risk,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Risk Score (0-100)'),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Safety Flags', style: TextStyle(fontWeight: FontWeight.w700)),
                  CheckboxListTile(
                    value: _hasBattery,
                    onChanged: (v) => setState(() => _hasBattery = v ?? false),
                    title: const Text('Contains battery (lithium or power bank)'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: _hasLiquid,
                    onChanged: (v) => setState(() => _hasLiquid = v ?? false),
                    title: const Text('Contains liquids/aerosols/perfume'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: _hasMedicine,
                    onChanged: (v) => setState(() => _hasMedicine = v ?? false),
                    title: const Text('Contains medicine/supplements'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _attest,
            onChanged: (v) => setState(() => _attest = v ?? false),
            title: const Text('I confirm the information is accurate and the package does not contain prohibited items.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: canSubmit && _myRequests.isNotEmpty ? _submit : null,
            child: const Text('Submit Package Verification'),
          ),
          const Divider(height: 28),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          const Text('My Package Verifications', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._items.map((e) => Card(
                child: ListTile(
                  title: Text('Request ${e['request_id']} - ${e['status']}'),
                  subtitle: Text('Risk ${e['risk_score']} | ${e['declared_contents']}'),
                ),
              )),
          ],
        ),
      ),
    );
  }
}
