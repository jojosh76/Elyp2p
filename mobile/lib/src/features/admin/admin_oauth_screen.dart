import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class AdminOAuthScreen extends StatefulWidget {
  const AdminOAuthScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<AdminOAuthScreen> createState() => _AdminOAuthScreenState();
}

class _AdminOAuthScreenState extends State<AdminOAuthScreen> {
  bool _loading = true;
  String? _error;
  final _models = <String, _ProviderFormModel>{
    'google': _ProviderFormModel(),
    'apple': _ProviderFormModel(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final model in _models.values) {
      model.clientID.dispose();
      model.iosClientID.dispose();
      model.webClientID.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.adminOAuthProviders();
      for (final row in rows) {
        final map = (row as Map).cast<String, dynamic>();
        final provider = (map['provider'] as String? ?? '').trim().toLowerCase();
        final model = _models[provider];
        if (model == null) continue;
        model.enabled = map['enabled'] as bool? ?? true;
        model.clientID.text = map['client_id'] as String? ?? '';
        model.iosClientID.text = map['ios_client_id'] as String? ?? '';
        model.webClientID.text = map['web_client_id'] as String? ?? '';
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String provider) async {
    final model = _models[provider]!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.adminUpsertOAuthProvider(
        provider: provider,
        enabled: model.enabled,
        clientID: model.clientID.text.trim(),
        iosClientID: model.iosClientID.text.trim(),
        webClientID: model.webClientID.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_title(provider)} OAuth config saved')),
      );
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _title(String provider) => provider == 'google' ? 'Google' : 'Apple';

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Text(
              'OAuth Providers',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure production client IDs used by mobile/web clients.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Card(
                color: const Color(0xFFFFE7E7),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFF8A1F1F))),
                ),
              ),
            _providerCard('google'),
            _providerCard('apple'),
          ],
        ),
      ),
    );
  }

  Widget _providerCard(String provider) {
    final model = _models[provider]!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(provider == 'google' ? Icons.g_mobiledata : Icons.apple),
                const SizedBox(width: 8),
                Text(_title(provider), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                Switch(
                  value: model.enabled,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() {
                            model.enabled = v;
                          }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: model.clientID,
              decoration: const InputDecoration(
                labelText: 'Client ID',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: model.iosClientID,
              decoration: const InputDecoration(
                labelText: 'iOS Client ID',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: model.webClientID,
              decoration: const InputDecoration(
                labelText: 'Web Client ID',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _loading ? null : () => _save(provider),
              icon: const Icon(Icons.save),
              label: Text(_loading ? 'Saving...' : 'Save ${_title(provider)}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderFormModel {
  bool enabled = true;
  final TextEditingController clientID = TextEditingController();
  final TextEditingController iosClientID = TextEditingController();
  final TextEditingController webClientID = TextEditingController();
}
