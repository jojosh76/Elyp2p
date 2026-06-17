import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';
import '../../widgets/animated_entry.dart';
import '../auth/auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _bio = TextEditingController();
  final _address = TextEditingController();
  final _country = TextEditingController();
  String _avatarData = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _bio.dispose();
    _address.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await widget.api.profile();
      _fullName.text = (user['full_name'] ?? '').toString();
      _avatarData = (user['avatar_url'] ?? '').toString();
      _phone.text = (user['phone'] ?? '').toString();
      _bio.text = (user['bio'] ?? '').toString();
      _address.text = (user['permanent_address'] ?? '').toString();
      _country.text = (user['country_of_residence'] ?? '').toString();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.updateProfile({
        'full_name': _fullName.text.trim(),
        'avatar_url': _avatarData.trim(),
        'phone': _phone.text.trim(),
        'bio': _bio.text.trim(),
        'permanent_address': _address.text.trim(),
        'country_of_residence': _country.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatarFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime = _mimeByFileName(file.name);
    setState(() {
      _avatarData = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _deleteMyAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
            'This will permanently delete your account from the backend. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.deleteMe();
      await widget.api.clearSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthScreen(api: widget.api)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mimeByFileName(String name) {
    final l = name.toLowerCase();
    if (l.endsWith('.png')) return 'image/png';
    if (l.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  ImageProvider? _avatarProvider(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('data:image/') && v.contains('base64,')) {
      final b64 = v.split('base64,').last;
      try {
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
    final avatar = _avatarData.trim();
    final provider = _avatarProvider(avatar);
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsivePage(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            AnimatedEntry(
              child: Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundImage: provider,
                  child: provider == null
                      ? const Icon(Icons.person, size: 40)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedEntry(
              delay: const Duration(milliseconds: 40),
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _pickAvatarFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('Choose Photo from Gallery'),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedEntry(
                delay: const Duration(milliseconds: 80),
                child: TextField(
                    controller: _fullName,
                    decoration: const InputDecoration(labelText: 'Full Name'))),
            const SizedBox(height: 8),
            AnimatedEntry(
                delay: const Duration(milliseconds: 110),
                child: TextField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Phone'))),
            const SizedBox(height: 8),
            AnimatedEntry(
                delay: const Duration(milliseconds: 140),
                child: TextField(
                    controller: _country,
                    decoration: const InputDecoration(
                        labelText: 'Country of Residence'))),
            const SizedBox(height: 8),
            AnimatedEntry(
                delay: const Duration(milliseconds: 170),
                child: TextField(
                    controller: _address,
                    decoration:
                        const InputDecoration(labelText: 'Permanent Address'))),
            const SizedBox(height: 8),
            AnimatedEntry(
                delay: const Duration(milliseconds: 200),
                child: TextField(
                  controller: _bio,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Bio'),
                )),
            const SizedBox(height: 14),
            if (_error != null)
              AnimatedEntry(
                  delay: const Duration(milliseconds: 240),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red))),
            AnimatedEntry(
                delay: const Duration(milliseconds: 260),
                child: FilledButton.icon(
                  onPressed: _loading ? null : _save,
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Profile'),
                )),
            const SizedBox(height: 8),
            AnimatedEntry(
                delay: const Duration(milliseconds: 300),
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _deleteMyAccount,
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text('Delete My Account',
                      style: TextStyle(color: Colors.red)),
                )),
          ],
        ),
      ),
    );
  }
}
