import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../admin/admin_dashboard_screen.dart';
import '../kyc/kyc_screen.dart';
import '../../widgets/responsive_page.dart';
import '../../widgets/animated_entry.dart';
import '../listings/listings_screen.dart';
import '../my_work/my_work_screen.dart';
import '../notifications/notifications_screen.dart';
import '../package_verification/package_verification_screen.dart';
import '../profile/profile_screen.dart';
import '../requests/requests_screen.dart';
import '../tracking/tracking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, this.onLogout});
  final ApiClient api;
  final VoidCallback? onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _backendOnline = true;
  String _kycStatus = 'unverified';
  int _unreadNotifications = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkBackend();
    _timer =
        Timer.periodic(const Duration(seconds: 20), (_) => _checkBackend());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkBackend() async {
    final ok = await widget.api.healthz();
    String status = _kycStatus;
    int unread = _unreadNotifications;
    try {
      final me = await widget.api.me();
      status = (me['kyc_status'] ?? 'unverified').toString();
      unread = await widget.api.myNotificationsUnreadCount();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _backendOnline = ok;
        _kycStatus = status;
        _unreadNotifications = unread;
      });
    }
  }

  Future<void> _logout() async {
    await widget.api.clearSession();
    if (widget.onLogout != null) {
      widget.onLogout!();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.api.role == 'admin') {
      return AdminDashboardScreen(api: widget.api, onLogout: _logout);
    }

    final isTraveler = widget.api.role == 'traveler';
    final isClient = widget.api.role == 'client';
    final sections = <_HomeSection>[
      _HomeSection(
          label: 'Profile',
          icon: Icons.person,
          page: ProfileScreen(api: widget.api),
          primary: true),
      _HomeSection(
          label: 'Alerts',
          icon: Icons.notifications,
          page: NotificationsScreen(api: widget.api),
          primary: true),
      _HomeSection(
          label: 'My Work',
          icon: Icons.work,
          page: MyWorkScreen(api: widget.api),
          primary: true),
      if (isTraveler)
        _HomeSection(
            label: 'Listings',
            icon: Icons.flight_takeoff,
            page: ListingsScreen(api: widget.api),
            primary: false),
      if (isTraveler)
        _HomeSection(
            label: 'Requests',
            icon: Icons.inventory_2,
            page: RequestsScreen(api: widget.api),
            primary: false),
      if (isTraveler)
        _HomeSection(
            label: 'KYC',
            icon: Icons.badge,
            page: KYCScreen(api: widget.api),
            primary: false),
      if (isClient)
        _HomeSection(
            label: 'Requests',
            icon: Icons.inventory_2,
            page: RequestsScreen(api: widget.api),
            primary: true),
      if (isClient)
        _HomeSection(
            label: 'Listings',
            icon: Icons.flight_takeoff,
            page: ListingsScreen(api: widget.api),
            primary: false),
      if (isClient)
        _HomeSection(
            label: 'Package',
            icon: Icons.shield,
            page: PackageVerificationScreen(api: widget.api),
            primary: false),
      _HomeSection(
          label: 'Tracking',
          icon: Icons.route,
          page: TrackingScreen(api: widget.api),
          primary: false),
    ];
    if (_index < 0 || _index >= sections.length) {
      _index = 0;
    }
    final primaryIndices = <int>[];
    final moreIndices = <int>[];
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].primary && primaryIndices.length < 3) {
        primaryIndices.add(i);
      } else {
        moreIndices.add(i);
      }
    }
    final navSelected =
        primaryIndices.contains(_index) ? primaryIndices.indexOf(_index) : 3;

    return Scaffold(
      appBar: AppBar(
        title: Text('Elysian Flee (${widget.api.role})'),
        actions: [
          Icon(
            _backendOnline ? Icons.cloud_done : Icons.cloud_off,
            color: _backendOnline ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () async {
              try {
                final me = await widget.api.me();
                if (mounted) {
                  setState(() => _kycStatus =
                      (me['kyc_status'] ?? 'unverified').toString());
                }
              } catch (_) {}
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('KYC: ${_kycStatus.toUpperCase()}')),
              );
            },
            icon: Icon(
              Icons.verified_user,
              color: _kycStatus == 'verified' ? Colors.green : Colors.red,
            ),
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ResponsivePage(
        child: sections[_index].page,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navSelected,
        onDestinationSelected: (v) async {
          if (v < primaryIndices.length) {
            setState(() => _index = primaryIndices[v]);
            return;
          }
          if (!mounted) return;
          final selected = await showModalBottomSheet<int>(
            context: context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text('More',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ...moreIndices.asMap().entries.map((entry) {
                    final i = entry.key;
                    final idx = entry.value;
                    return AnimatedEntry(
                      delay: Duration(milliseconds: 40 * i),
                      child: ListTile(
                        leading: Icon(sections[idx].icon),
                        title: Text(sections[idx].label),
                        onTap: () => Navigator.pop(context, idx),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          );
          if (selected != null && mounted) {
            setState(() => _index = selected);
          }
        },
        destinations: [
          ...primaryIndices.map((idx) => NavigationDestination(
                icon: sections[idx].label == 'Alerts'
                    ? Badge(
                        isLabelVisible: _unreadNotifications > 0,
                        label: Text('$_unreadNotifications'),
                        child: Icon(sections[idx].icon),
                      )
                    : Icon(sections[idx].icon),
                label: sections[idx].label,
              )),
          const NavigationDestination(
              icon: Icon(Icons.grid_view_rounded), label: 'More'),
        ],
      ),
    );
  }
}

class _HomeSection {
  const _HomeSection({
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
