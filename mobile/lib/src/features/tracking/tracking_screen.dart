import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  List<dynamic> _myMatches = [];
  String _selectedMatchId = '';
  String _status = 'picked_up';
  final _location = TextEditingController(text: 'Paris');
  final _notes = TextEditingController();
  List<dynamic> _events = [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    try {
      _myMatches = await widget.api.myMatches();
      if (_selectedMatchId.isEmpty && _myMatches.isNotEmpty) {
        _selectedMatchId = (_myMatches.first['id'] ?? '').toString();
      }
      await _load();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() {});
    }
  }

  Future<void> _load() async {
    if (_selectedMatchId.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _events = await widget.api.listTracking(_selectedMatchId.trim());
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createEvent() async {
    try {
      if (_selectedMatchId.trim().isEmpty) {
        throw Exception('Select a match first');
      }
      final now = DateTime.now().toUtc();
      await widget.api.addTrackingEvent({
        'match_id': _selectedMatchId.trim(),
        'status': _status.trim(),
        'location': _location.text.trim(),
        'notes': _notes.text.trim(),
        'occurred_at': now.toIso8601String(),
      });
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
    final canAddEvent =
        widget.api.role == 'traveler' || widget.api.role == 'admin';
    return RefreshIndicator(
      onRefresh: _loadMatches,
      child: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_myMatches.isEmpty)
              const Text('No matches available yet.')
            else
              DropdownButtonFormField<String>(
                initialValue:
                    _selectedMatchId.isEmpty ? null : _selectedMatchId,
                items: _myMatches
                    .map((e) => (e as Map).cast<String, dynamic>())
                    .map((e) => DropdownMenuItem<String>(
                          value: (e['id'] ?? '').toString(),
                          child: Text(
                              'Match | price ${e['agreed_price'] ?? 0} | ${e['status'] ?? ''}'),
                        ))
                    .toList(),
                onChanged: (v) async {
                  setState(() => _selectedMatchId = v ?? '');
                  await _load();
                },
                decoration: const InputDecoration(labelText: 'Select Match'),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: const [
                DropdownMenuItem(value: 'picked_up', child: Text('Picked Up')),
                DropdownMenuItem(
                    value: 'in_transit', child: Text('In Transit')),
                DropdownMenuItem(
                    value: 'arrived_destination',
                    child: Text('Arrived Destination')),
                DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'picked_up'),
              decoration: const InputDecoration(labelText: 'Status'),
            ),
            const SizedBox(height: 8),
            TextField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 8),
            TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes')),
            const SizedBox(height: 6),
            Text(
              'Event date/time is captured automatically from this phone.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            if (canAddEvent) ...[
              Row(
                children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: _createEvent,
                          child: const Text('Add Event'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: OutlinedButton(
                          onPressed: _load,
                          child: const Text('Load Timeline'))),
                ],
              ),
            ] else ...[
              OutlinedButton(
                  onPressed: _load, child: const Text('Load Timeline')),
              const SizedBox(height: 6),
              const Text(
                  'Only traveler/admin accounts can add tracking events.'),
            ],
            const Divider(height: 28),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ..._events.map((e) {
              final occurredAt =
                  (e['occurred_at'] ?? e['created_at'] ?? '').toString();
              return Card(
                child: ListTile(
                  title: Text('${e['status']} @ ${e['location']}'),
                  subtitle: Text('${e['notes'] ?? ''}\n$occurredAt'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
