import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';
import '../admin/admin_finance_screen.dart';
import '../admin/admin_kyc_screen.dart';
import '../admin/admin_oauth_screen.dart';
import '../admin/admin_packages_screen.dart';
import '../kyc/kyc_screen.dart';
import '../my_work/my_work_screen.dart';
import '../package_verification/package_verification_screen.dart';
import '../profile/profile_screen.dart';
import '../tracking/tracking_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
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
      _items = await widget.api.myNotifications();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await widget.api.markNotificationRead(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await widget.api.deleteNotification(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  List<_NotifAction> _actionsFor(Map<String, dynamic> item) {
    final role = widget.api.role;
    final title = ((item['title'] as String?) ?? '').toLowerCase();
    final message = ((item['message'] as String?) ?? '').toLowerCase();
    final type = ((item['type'] as String?) ?? '').toLowerCase();
    final blob = '$title $message $type';
    if (role == 'admin') {
      if (blob.contains('kyc')) {
        return [const _NotifAction('Open KYC Queue', Icons.badge, _NotifTarget.adminKyc)];
      }
      if (blob.contains('package')) {
        return [const _NotifAction('Open Package Queue', Icons.shield, _NotifTarget.adminPackages)];
      }
      if (blob.contains('oauth')) {
        return [const _NotifAction('Open OAuth Config', Icons.key, _NotifTarget.adminOAuth)];
      }
      if (blob.contains('escrow') || blob.contains('finance') || blob.contains('commission')) {
        return [const _NotifAction('Open Finance', Icons.attach_money, _NotifTarget.adminFinance)];
      }
      return [const _NotifAction('Open KYC Queue', Icons.badge, _NotifTarget.adminKyc)];
    }
    if (role == 'traveler') {
      if (blob.contains('kyc')) {
        return [const _NotifAction('Open KYC', Icons.badge, _NotifTarget.kyc)];
      }
      if (blob.contains('tracking') || blob.contains('delivery')) {
        return [const _NotifAction('Open Tracking', Icons.route, _NotifTarget.tracking)];
      }
      if (blob.contains('escrow') || blob.contains('match')) {
        return [const _NotifAction('Open My Work', Icons.work, _NotifTarget.myWork)];
      }
      return [const _NotifAction('Open My Work', Icons.work, _NotifTarget.myWork)];
    }
    if (blob.contains('package')) {
      return [const _NotifAction('Open Package Verification', Icons.shield, _NotifTarget.packageVerification)];
    }
    if (blob.contains('tracking') || blob.contains('delivery')) {
      return [const _NotifAction('Open Tracking', Icons.route, _NotifTarget.tracking)];
    }
    if (blob.contains('escrow') || blob.contains('match')) {
      return [const _NotifAction('Open My Work', Icons.work, _NotifTarget.myWork)];
    }
    return [const _NotifAction('Open Profile', Icons.person, _NotifTarget.profile)];
  }

  Future<void> _openTarget(_NotifTarget target) async {
    Widget page;
    switch (target) {
      case _NotifTarget.kyc:
        page = KYCScreen(api: widget.api);
        break;
      case _NotifTarget.packageVerification:
        page = PackageVerificationScreen(api: widget.api);
        break;
      case _NotifTarget.tracking:
        page = TrackingScreen(api: widget.api);
        break;
      case _NotifTarget.myWork:
        page = MyWorkScreen(api: widget.api);
        break;
      case _NotifTarget.profile:
        page = ProfileScreen(api: widget.api);
        break;
      case _NotifTarget.adminKyc:
        page = AdminKYCScreen(api: widget.api);
        break;
      case _NotifTarget.adminPackages:
        page = AdminPackagesScreen(api: widget.api);
        break;
      case _NotifTarget.adminFinance:
        page = AdminFinanceScreen(api: widget.api);
        break;
      case _NotifTarget.adminOAuth:
        page = AdminOAuthScreen(api: widget.api);
        break;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openNotification(Map<String, dynamic> item) async {
    final id = (item['id'] as String?) ?? '';
    final actions = _actionsFor(item);
    if (!mounted) return;
    final selected = await showModalBottomSheet<_NotifAction>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text((item['title'] as String?) ?? 'Notification',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            Text((item['message'] as String?) ?? ''),
            const SizedBox(height: 14),
            ...actions.map((a) => ListTile(
                  leading: Icon(a.icon),
                  title: Text(a.label),
                  onTap: () => Navigator.pop(context, a),
                )),
            if (id.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.done_all),
                title: const Text('Mark as Read'),
                onTap: () => Navigator.pop(context, const _NotifAction('Mark as Read', Icons.done_all, _NotifTarget.profile, markReadOnly: true)),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (id.isNotEmpty) {
      await _markRead(id);
    }
    if (!selected.markReadOnly) {
      await _openTarget(selected.target);
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
            const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 10),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (!_loading && _items.isEmpty) const Text('No notifications yet.'),
            ..._items.map((e) {
              final item = (e as Map).cast<String, dynamic>();
              final read = item['read_at'] != null;
              final actions = _actionsFor(item);
              return Card(
                child: ListTile(
                  onTap: () => _openNotification(item),
                  title: Text(
                    (item['title'] as String?) ?? 'Notification',
                    style: TextStyle(fontWeight: read ? FontWeight.w500 : FontWeight.w700),
                  ),
                  subtitle: Text((item['message'] as String?) ?? ''),
                  trailing: SizedBox(
                    width: 170,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!read)
                          IconButton(
                            tooltip: 'Mark read',
                            onPressed: () => _markRead((item['id'] as String?) ?? ''),
                            icon: const Icon(Icons.done_all, color: Colors.green),
                          ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () => _deleteNotification((item['id'] as String?) ?? ''),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        IconButton(
                          tooltip: actions.first.label,
                          onPressed: () => _openTarget(actions.first.target),
                          icon: Icon(actions.first.icon),
                        ),
                      ],
                    ),
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

enum _NotifTarget {
  profile,
  myWork,
  tracking,
  kyc,
  packageVerification,
  adminKyc,
  adminPackages,
  adminFinance,
  adminOAuth,
}

class _NotifAction {
  const _NotifAction(this.label, this.icon, this.target, {this.markReadOnly = false});
  final String label;
  final IconData icon;
  final _NotifTarget target;
  final bool markReadOnly;
}
