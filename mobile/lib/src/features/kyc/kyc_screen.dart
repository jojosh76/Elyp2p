import 'dart:convert';
import 'package:country_picker/country_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class KYCScreen extends StatefulWidget {
  const KYCScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<KYCScreen> createState() => _KYCScreenState();
}

class _KYCScreenState extends State<KYCScreen> {
  final _picker = ImagePicker();
  final _homeAddress = TextEditingController();
  final _docType = TextEditingController(text: 'passport_with_id_or_residence');
  String _homeCountry = 'United States';
  String _secondaryDocType = 'id_card';

  String _passportFront = '';
  String _passportBack = '';
  String _secondaryFront = '';
  String _secondaryBack = '';

  List<dynamic> _items = [];
  String? _error;
  bool _loading = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _homeAddress.dispose();
    _docType.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _items = await widget.api.myKYC();
      await widget.api.me();
      _homeAddress.text = (widget.api.currentUser?['permanent_address'] as String?) ?? _homeAddress.text;
      final country = (widget.api.currentUser?['country_of_residence'] as String?)?.trim() ?? '';
      if (country.isNotEmpty) _homeCountry = country;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage(ValueChanged<String> onPicked, {required bool camera}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return;
    if (!mounted) return;
    setState(() => onPicked(file.path));
  }

  Future<void> _pickPdf(ValueChanged<String> onPicked) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.first.path ?? '';
    if (path.isEmpty || !mounted) return;
    setState(() => onPicked(path));
  }

  Future<void> _chooseSource(String title, ValueChanged<String> onPicked) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text('Take $title Photo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(onPicked, camera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('Pick $title from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(onPicked, camera: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text('Pick $title PDF'),
              onTap: () async {
                Navigator.pop(context);
                await _pickPdf(onPicked);
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
    if (_passportFront.isEmpty ||
        _passportBack.isEmpty ||
        _secondaryFront.isEmpty ||
        _secondaryBack.isEmpty ||
        _homeAddress.text.trim().isEmpty ||
        _homeCountry.trim().isEmpty) {
      setState(() => _error = 'Upload passport front/back, ID or permit front/back, and fill home country/address');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.api.me();
      final fullName =
          (widget.api.currentUser?['full_name'] as String?)?.trim() ?? '';
      if (fullName.isEmpty) {
        throw Exception('Full name is missing on your profile. Update it in Profile first.');
      }

      await widget.api.updateProfile({
        'full_name': fullName,
        'country_of_residence': _homeCountry.trim(),
        'permanent_address': _homeAddress.text.trim(),
      });

      final documentReference = jsonEncode({
        'passport': {'front': _passportFront, 'back': _passportBack},
        _secondaryDocType: {'front': _secondaryFront, 'back': _secondaryBack},
      });
      final addressProofRef = jsonEncode({
        'home_country': _homeCountry.trim(),
        'home_address': _homeAddress.text.trim(),
      });

      await widget.api.submitKYC(
        documentType: _docType.text.trim(),
        documentReference: documentReference,
        addressProofRef: addressProofRef,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KYC submitted for admin review')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kycStatus = widget.api.currentUser?['kyc_status'] ?? 'unknown';
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'KYC Upload Center v2',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text('Current KYC Status: $kycStatus', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showCountryPicker(
                        context: context,
                        showPhoneCode: false,
                        onSelect: (country) => setState(() => _homeCountry = country.name),
                      );
                    },
                    icon: const Icon(Icons.public),
                    label: Text('Home Country: $_homeCountry'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _homeAddress,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Home Address'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _secondaryDocType,
              items: const [
                DropdownMenuItem(value: 'id_card', child: Text('ID Card')),
                DropdownMenuItem(value: 'residence_permit', child: Text('Residence Permit')),
              ],
              onChanged: (v) => setState(() => _secondaryDocType = v ?? 'id_card'),
              decoration: const InputDecoration(labelText: 'Second Document Type'),
            ),
            const SizedBox(height: 14),
            const Text('Passport', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge),
              title: const Text('Passport Front'),
              subtitle: Text(_short(_passportFront)),
              trailing: OutlinedButton(
                onPressed: () => _chooseSource('Passport Front', (v) => _passportFront = v),
                child: const Text('Upload'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Passport Back'),
              subtitle: Text(_short(_passportBack)),
              trailing: OutlinedButton(
                onPressed: () => _chooseSource('Passport Back', (v) => _passportBack = v),
                child: const Text('Upload'),
              ),
            ),
            const SizedBox(height: 10),
            Text(_secondaryDocType == 'id_card' ? 'ID Card' : 'Residence Permit',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.credit_card),
              title: Text('${_secondaryDocType == 'id_card' ? 'ID Card' : 'Residence Permit'} Front'),
              subtitle: Text(_short(_secondaryFront)),
              trailing: OutlinedButton(
                onPressed: () => _chooseSource('Document Front', (v) => _secondaryFront = v),
                child: const Text('Upload'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.credit_card_off),
              title: Text('${_secondaryDocType == 'id_card' ? 'ID Card' : 'Residence Permit'} Back'),
              subtitle: Text(_short(_secondaryBack)),
              trailing: OutlinedButton(
                onPressed: () => _chooseSource('Document Back', (v) => _secondaryBack = v),
                child: const Text('Upload'),
              ),
            ),
            const SizedBox(height: 10),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit KYC For Review'),
            ),
            const Divider(height: 28),
            if (_loading) const Center(child: CircularProgressIndicator()),
            const Text('My KYC Submissions', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._items.map((e) => Card(
                  child: ListTile(
                    title: Text('${e['document_type']} - ${e['status']}'),
                    subtitle: Text(e['review_notes'] ?? ''),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
