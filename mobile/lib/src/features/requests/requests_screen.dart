import 'dart:convert';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final _picker = ImagePicker();

  List<dynamic> _items = [];
  String? _error;
  bool _loading = false;
  bool _submitting = false;

  final _origin = TextEditingController(text: 'Paris');
  final _destination = TextEditingController(text: 'Lagos');
  final _weight = TextEditingController(text: '2.5');
  final _description = TextEditingController(text: 'Phone accessories');
  final _declaredValue = TextEditingController(text: '180');
  final _recipientName = TextEditingController(text: 'Recipient');
  final _recipientPhoneLocal = TextEditingController();
  final _dropoffAddress = TextEditingController(text: 'Full dropoff address');
  final _dropoffInstructions = TextEditingController(text: 'Call on arrival');

  String _destinationType = 'city';
  String _recipientCountryCode = '+1';
  String _recipientCountryName = 'United States';
  String _recipientPhotoData = '';
  static const List<_CountryPreset> _countryPresets = [
    _CountryPreset(name: 'United States', code: '+1'),
    _CountryPreset(name: 'United Kingdom', code: '+44'),
    _CountryPreset(name: 'Nigeria', code: '+234'),
    _CountryPreset(name: 'France', code: '+33'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _weight.dispose();
    _description.dispose();
    _declaredValue.dispose();
    _recipientName.dispose();
    _recipientPhoneLocal.dispose();
    _dropoffAddress.dispose();
    _dropoffInstructions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.api.role == 'traveler') {
        _items = await widget.api.listDeliveryRequests();
      } else {
        _items = await widget.api.myRequests();
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _matchAsTraveler(Map<String, dynamic> request) async {
    if (widget.api.role != 'traveler') return;
    try {
      final myListings = await widget.api.myListings();
      if (myListings.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create a traveler listing first.')),
        );
        return;
      }

      String selectedListingID = (myListings.first['id'] as String?) ?? '';
      final priceCtrl = TextEditingController(text: '25');
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Match With Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Request: ${request['origin']} -> ${request['destination']}'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedListingID,
                items: myListings
                    .map((l) => DropdownMenuItem<String>(
                          value: (l['id'] as String?) ?? '',
                          child: Text('${l['origin']} -> ${l['destination']}'),
                        ))
                    .toList(),
                onChanged: (v) => selectedListingID = v ?? '',
                decoration: const InputDecoration(labelText: 'Your Listing'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Agreed Price (USD)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create Match'),
            ),
          ],
        ),
      );
      if (ok != true) {
        priceCtrl.dispose();
        return;
      }
      final agreedPrice = double.tryParse(priceCtrl.text.trim()) ?? 0;
      final selectedListing = myListings
          .cast<Map>()
          .map((e) => e.cast<String, dynamic>())
          .firstWhere(
            (l) => (l['id'] ?? '').toString() == selectedListingID,
            orElse: () => <String, dynamic>{},
          );
      final estimatedDeliveryAt = (selectedListing['arrival_date'] ?? '').toString();
      await widget.api.createMatch(
        listingID: selectedListingID,
        requestID: (request['id'] as String?) ?? '',
        agreedPrice: agreedPrice,
        estimatedDeliveryAt: estimatedDeliveryAt.isEmpty
            ? DateTime.now().toIso8601String()
            : estimatedDeliveryAt,
      );
      priceCtrl.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Match created successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _pickRecipientPhoto() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickFrom(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose From Gallery'),
              onTap: () async {
                Navigator.pop(context);
                await _pickFrom(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFrom(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    final mime = _mimeByFileName(file.name);
    setState(() {
      _recipientPhotoData = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  String _mimeByFileName(String name) {
    final l = name.toLowerCase();
    if (l.endsWith('.png')) return 'image/png';
    if (l.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _buildRecipientPhone() {
    final localDigits = _recipientPhoneLocal.text.replaceAll(RegExp(r'\D'), '');
    if (localDigits.isEmpty) return '';
    return '$_recipientCountryCode$localDigits';
  }

  bool _isLikelyE164(String input) {
    final v = input.trim();
    if (!v.startsWith('+')) return false;
    if (v.length < 8 || v.length > 16) return false;
    return RegExp(r'^\+\d+$').hasMatch(v);
  }

  Future<void> _create() async {
    try {
      final recipientPhone = _buildRecipientPhone();
      if (_recipientName.text.trim().isEmpty) {
        throw Exception('Recipient name is required');
      }
      if (!_isLikelyE164(recipientPhone)) {
        throw Exception(
          'Recipient phone must include country code, e.g. +14155550123',
        );
      }
      if (_dropoffAddress.text.trim().isEmpty) {
        throw Exception('Precise dropoff address is required');
      }
      setState(() => _submitting = true);
      await widget.api.createDeliveryRequest({
        'origin': _origin.text.trim(),
        'destination_type': _destinationType,
        'destination': _destination.text.trim(),
        'recipient_name': _recipientName.text.trim(),
        'recipient_phone': recipientPhone,
        'recipient_photo_url': _recipientPhotoData.trim(),
        'dropoff_address': _dropoffAddress.text.trim(),
        'dropoff_instructions': _dropoffInstructions.text.trim(),
        'weight_kg': double.tryParse(_weight.text) ?? 0,
        'package_description': _description.text.trim(),
        'declared_value': double.tryParse(_declaredValue.text) ?? 0,
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery request created.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  ImageProvider? _imageProviderFor(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('data:image/') && v.contains('base64,')) {
      try {
        final b64 = v.split('base64,').last;
        final Uint8List bytes = base64Decode(b64);
        return MemoryImage(bytes);
      } catch (_) {
        return null;
      }
    }
    if (v.startsWith('http://') || v.startsWith('https://')) {
      return NetworkImage(v);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final canCreateRequest =
        widget.api.role == 'client' || widget.api.role == 'admin';
    final previewPhone = _buildRecipientPhone();
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canCreateRequest) ...[
              const Text(
                'Create Delivery Request',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 6),
              const Text(
                'Fill sender, recipient, and dropoff details carefully. Recipient phone must include country code.',
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Route & Package',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _origin,
                        decoration: const InputDecoration(labelText: 'Origin'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _destination,
                        decoration: const InputDecoration(labelText: 'Destination'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _destinationType,
                        items: const [
                          DropdownMenuItem(value: 'city', child: Text('City')),
                          DropdownMenuItem(value: 'country', child: Text('Country')),
                        ],
                        onChanged: (v) =>
                            setState(() => _destinationType = v ?? 'city'),
                        decoration:
                            const InputDecoration(labelText: 'Destination Type'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Weight (kg)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _description,
                        decoration: const InputDecoration(
                          labelText: 'Package Description',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _declaredValue,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Declared Value'),
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recipient Details',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _recipientName,
                        decoration:
                            const InputDecoration(labelText: 'Recipient Name'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                showCountryPicker(
                                  context: context,
                                  showPhoneCode: true,
                                  onSelect: (country) {
                                    setState(() {
                                      _recipientCountryName = country.name;
                                      _recipientCountryCode =
                                          '+${country.phoneCode}';
                                    });
                                  },
                                );
                              },
                              icon: const Icon(Icons.public),
                              label: Text(_recipientCountryCode),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: TextField(
                              controller: _recipientPhoneLocal,
                              keyboardType: TextInputType.phone,
                              inputFormatters: const [_LocalPhoneFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'Recipient Phone (local digits)',
                                hintText: 'e.g. 4155550123',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _countryPresets
                            .map((preset) => ChoiceChip(
                                  label: Text(
                                    '${preset.name.split(' ').first} ${preset.code}',
                                  ),
                                  selected: _recipientCountryCode == preset.code,
                                  onSelected: (_) {
                                    setState(() {
                                      _recipientCountryCode = preset.code;
                                      _recipientCountryName = preset.name;
                                    });
                                  },
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Country: $_recipientCountryName\nFull number sent: ${previewPhone.isEmpty ? '(enter phone)' : previewPhone}\nUse international format with country code (example: +14155550123).',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: _imageProviderFor(_recipientPhotoData),
                            child: _recipientPhotoData.isEmpty
                                ? const Icon(Icons.person_outline)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickRecipientPhoto,
                              icon: const Icon(Icons.photo_camera),
                              label: Text(
                                _recipientPhotoData.isEmpty
                                    ? 'Upload Recipient Photo'
                                    : 'Change Recipient Photo',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dropoff',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _dropoffAddress,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Precise Dropoff Address',
                          hintText:
                              'Street, area, city, nearby landmark, building/floor',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _dropoffInstructions,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Dropoff Instructions',
                          hintText:
                              'Who to ask for, call before arrival, gate notes, etc.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _submitting ? null : _create,
                icon: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Create Request'),
              ),
              const Divider(height: 28),
            ] else ...[
              const Text(
                'Delivery requests are created by client accounts. As a traveler, publish your trip in Listings.',
              ),
              const Divider(height: 28),
            ],
            Text(
              widget.api.role == 'traveler' ? 'Open Requests' : 'My Requests',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ..._items.map((item) {
              final req = (item as Map).cast<String, dynamic>();
              final photo = _imageProviderFor(
                (req['recipient_photo_url'] ?? req['client_avatar_url'] ?? '')
                    .toString(),
              );
              return Card(
                child: ListTile(
                  onTap: widget.api.role == 'traveler'
                      ? () => _matchAsTraveler(req)
                      : null,
                  leading: CircleAvatar(
                    backgroundImage: photo,
                    child: photo == null
                        ? Text(
                            ((req['recipient_name'] ?? req['client_name'] ?? 'C')
                                        .toString()
                                        .trim()
                                        .isNotEmpty
                                    ? (req['recipient_name'] ??
                                            req['client_name'] ??
                                            'C')
                                        .toString()
                                        .trim()[0]
                                    : 'C')
                                .toUpperCase(),
                          )
                        : null,
                  ),
                  title: Text('${req['origin']} -> ${req['destination']}'),
                  subtitle: Text(
                    'Client: ${req['client_name'] ?? 'Unknown'}\nDeliver to: ${req['recipient_name'] ?? ''} | ${req['recipient_phone'] ?? ''}\nDropoff: ${req['dropoff_address'] ?? ''}\nWeight: ${req['weight_kg']}kg | Value: ${req['declared_value']}',
                  ),
                  trailing: widget.api.role == 'traveler'
                      ? const Icon(Icons.handshake)
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CountryPreset {
  const _CountryPreset({required this.name, required this.code});
  final String name;
  final String code;
}

class _LocalPhoneFormatter extends TextInputFormatter {
  const _LocalPhoneFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final groups = <String>[];
    for (var i = 0; i < digits.length; i += 3) {
      final end = (i + 3 < digits.length) ? i + 3 : digits.length;
      groups.add(digits.substring(i, end));
    }
    final formatted = groups.join(' ');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}