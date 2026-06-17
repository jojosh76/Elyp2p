import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import 'admin_finance_screen.dart';
import 'admin_kyc_screen.dart';
import 'admin_oauth_screen.dart';
import 'admin_packages_screen.dart';
import '../notifications/notifications_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.api, this.onLogout});
  final ApiClient api;
  final VoidCallback? onLogout;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _index = 0;
  int _unreadNotifications = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshUnread();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshUnread());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    try {
      final unread = await widget.api.myNotificationsUnreadCount();
      if (!mounted) return;
      setState(() => _unreadNotifications = unread);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final sections = <_AdminSection>[
      _AdminSection(label: 'KYC', icon: Icons.badge, page: AdminKYCScreen(api: widget.api), primary: true),
      _AdminSection(label: 'Packages', icon: Icons.shield, page: AdminPackagesScreen(api: widget.api), primary: true),
      _AdminSection(label: 'Alerts', icon: Icons.notifications, page: NotificationsScreen(api: widget.api), primary: true),
      _AdminSection(label: 'Finance', icon: Icons.attach_money, page: AdminFinanceScreen(api: widget.api), primary: false),
      _AdminSection(label: 'OAuth', icon: Icons.key, page: AdminOAuthScreen(api: widget.api), primary: false),
    ];
    if (_index < 0 || _index >= sections.length) {
      _index = 0;
    }
    final primaryIndices = <int>[0, 1, 2];
    final moreIndices = <int>[3, 4];
    final navSelected = primaryIndices.contains(_index) ? primaryIndices.indexOf(_index) : 3;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elysian Flee Admin'),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: sections[_index].page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navSelected,
        onDestinationSelected: (v) async {
          if (v < primaryIndices.length) {
            setState(() => _index = primaryIndices[v]);
            return;
          }
          final selected = await showModalBottomSheet<int>(
            context: context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text('More', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ...moreIndices.map((idx) => ListTile(
                        leading: Icon(sections[idx].icon),
                        title: Text(sections[idx].label),
                        onTap: () => Navigator.pop(context, idx),
                      )),
                ],
              ),
            ),
          );
          if (selected != null && mounted) {
            setState(() => _index = selected);
          }
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.badge), label: 'KYC'),
          const NavigationDestination(icon: Icon(Icons.shield), label: 'Packages'),
          NavigationDestination(
              icon: Badge(
                isLabelVisible: _unreadNotifications > 0,
                label: Text('$_unreadNotifications'),
                child: Icon(Icons.notifications),
              ),
              label: 'Alerts'),
          const NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'More'),
        ],
      ),
    );
  }
}

class _AdminSection {
  const _AdminSection({
    required this.label,
    required this.icon,
    required this.page,
    required this.primary,
  });
  final String label;
  final IconData icon;
  final Widget page;
  final bool primary;
}
