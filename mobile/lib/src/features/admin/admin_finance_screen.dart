import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class AdminFinanceScreen extends StatefulWidget {
  const AdminFinanceScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<dynamic> _escrows = [];
  List<dynamic> _users = [];

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
      _summary = await widget.api.adminCommissionSummary();
      _escrows = await widget.api.adminEscrows();
      _users = await widget.api.adminUsers();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
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
          const Text('Commission Summary', style: TextStyle(fontWeight: FontWeight.bold)),
          Card(
            child: ListTile(
              title: Text(
                'Released: ${_summary['released_escrows'] ?? 0} | '
                'Volume: ${_summary['total_volume'] ?? 0} | '
                'Commission: ${_summary['total_commission'] ?? 0}',
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Escrows', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._escrows.map((e) => Card(
                child: ListTile(
                  title: Text('${e['id']} ${e['amount']} ${e['currency']}'),
                  subtitle: Text('Status ${e['status']} | commission ${e['commission_amount']}'),
                ),
              )),
          const SizedBox(height: 8),
          const Text('Users', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._users.map((u) => Card(
                child: ListTile(
                  title: Text('${u['full_name']} (${u['role']})'),
                  subtitle: Text('${u['email']} | KYC ${u['kyc_status']}'),
                ),
              )),
          ],
        ),
      ),
    );
  }
}
