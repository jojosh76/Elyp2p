import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../api/api_client.dart';
import '../auth/auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _bio = TextEditingController();
  final _address = TextEditingController();
  final _country = TextEditingController();
  String _avatarData = '';
  bool _loading = false;
  bool _editing = false;
  String? _error;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
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
      _editing = false;
      _fadeCtrl.forward(from: 0);
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
      // Stay in view mode after save — Modify button always visible
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 10),
            Text('Profile saved'),
          ]),
          backgroundColor: const Color(0xFF1A7A5E),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
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
            'This will permanently delete your account. This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
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
    final provider = _avatarProvider(_avatarData.trim());
    final name = _fullName.text.trim().isEmpty ? 'Your Name' : _fullName.text.trim();
    final role = widget.api.role;

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Hero banner ──
            SliverToBoxAdapter(
              child: _HeroBanner(
                name: name,
                role: role,
                phone: _phone.text.trim(),
                country: _country.text.trim(),
                avatarProvider: provider,
                editing: _editing,
                loading: _loading,
                onPickAvatar: _pickAvatarFromGallery,
                onModify: () => setState(() => _editing = true),
              ),
            ),

            // ── Body ──
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 20),

                  // Personal info card
                  _InfoCard(
                    title: 'Personal info',
                    icon: Icons.person_outline_rounded,
                    children: [
                      _Field(
                        controller: _fullName,
                        label: 'Full Name',
                        icon: Icons.badge_outlined,
                        enabled: _editing && !_loading,
                      ),
                      _Field(
                        controller: _phone,
                        label: 'Phone',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        enabled: _editing && !_loading,
                      ),
                      _Field(
                        controller: _country,
                        label: 'Country of Residence',
                        icon: Icons.public_outlined,
                        enabled: _editing && !_loading,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Address & bio card
                  _InfoCard(
                    title: 'About',
                    icon: Icons.info_outline_rounded,
                    children: [
                      _Field(
                        controller: _address,
                        label: 'Permanent Address',
                        icon: Icons.home_outlined,
                        enabled: _editing && !_loading,
                      ),
                      _Field(
                        controller: _bio,
                        label: 'Bio',
                        icon: Icons.notes_outlined,
                        maxLines: 4,
                        enabled: _editing && !_loading,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Error
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: Colors.red.withValues(alpha: 0.30)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFFFB4AB), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFFFB4AB), fontSize: 13)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Action buttons ──
                  // Always show Modify. In edit mode add Save + Cancel.
                  if (_editing) ...[
                    _ActionButton(
                      onPressed: _loading ? null : _save,
                      loading: _loading,
                      icon: Icons.save_outlined,
                      label: 'Save Profile',
                      filled: true,
                    ),
                    const SizedBox(height: 10),
                    _ActionButton(
                      onPressed: _loading ? null : _load,
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      filled: false,
                    ),
                  ] else ...[
                    _ActionButton(
                      onPressed:
                          _loading ? null : () => setState(() => _editing = true),
                      icon: Icons.edit_outlined,
                      label: 'Modify Profile',
                      filled: true,
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Delete account — always visible
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _deleteMyAccount,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.delete_forever_outlined,
                        color: Colors.red, size: 20),
                    label: const Text('Delete My Account',
                        style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Hero banner — large cover + avatar overlap
// ══════════════════════════════════════════════════
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.name,
    required this.role,
    required this.phone,
    required this.country,
    required this.avatarProvider,
    required this.editing,
    required this.loading,
    required this.onPickAvatar,
    required this.onModify,
  });

  final String name, role, phone, country;
  final ImageProvider? avatarProvider;
  final bool editing, loading;
  final VoidCallback onPickAvatar, onModify;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Cover gradient
        Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                scheme.primary.withValues(alpha: 0.55),
                scheme.secondary.withValues(alpha: 0.40),
              ],
            ),
          ),
          child: Stack(children: [
            // Decorative circles
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -20,
              left: 40,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
          ]),
        ),

        // Avatar + info below cover
        Padding(
          padding: const EdgeInsets.only(top: 130),
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding:
                const EdgeInsets.fromLTRB(20, 56, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + role
                Text(
                  name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Chip(icon: Icons.account_circle_outlined, label: role),
                    if (country.isNotEmpty)
                      _Chip(icon: Icons.public_outlined, label: country),
                    if (phone.isNotEmpty)
                      _Chip(icon: Icons.phone_outlined, label: phone),
                    _Chip(
                      icon: editing
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                      label: editing ? 'Editing' : 'View mode',
                      highlight: editing,
                    ),
                  ],
                ),
                // Photo picker (editing only)
                if (editing) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : onPickAvatar,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose Photo from Gallery'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Avatar circle — overlapping the cover bottom edge
        Positioned(
          top: 110,
          left: 20,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  backgroundImage: avatarProvider,
                  child: avatarProvider == null
                      ? Icon(Icons.person,
                          size: 50,
                          color:
                              Theme.of(context).colorScheme.primary)
                      : null,
                ),
              ),
              // Camera badge
              if (editing)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: onPickAvatar,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Edit / pencil button top-right of cover
        Positioned(
          top: 12,
          right: 12,
          child: editing
              ? const SizedBox.shrink()
              : Material(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onModify,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.edit_outlined,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════
// Reusable info card
// ══════════════════════════════════════════════════
class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.title,
      required this.icon,
      required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Icon(icon,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
              ),
            ]),
          ),
          const SizedBox(height: 2),
          Divider(
              thickness: 1,
              height: 16,
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.10)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: List.generate(children.length, (i) => Column(
                children: [
                  children[i],
                  if (i < children.length - 1) const SizedBox(height: 10),
                ],
              )),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Text field wrapper
// ══════════════════════════════════════════════════
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    required this.enabled,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(
        fontSize: 14,
        color: enabled
            ? null
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: enabled
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: 0.3)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Primary / secondary action button
// ══════════════════════════════════════════════════
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading && filled)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        else
          Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );

    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14));

    if (filled) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: shape,
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: shape,
        ),
        child: child,
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Small info chip
// ══════════════════════════════════════════════════
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.highlight = false});

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primary.withValues(alpha: 0.15)
            : scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: highlight
                ? scheme.primary.withValues(alpha: 0.35)
                : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: highlight ? scheme.primary : scheme.onSurface.withValues(alpha: 0.65)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlight
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}