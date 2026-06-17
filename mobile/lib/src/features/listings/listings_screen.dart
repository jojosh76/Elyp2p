import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';

class ListingsScreen extends StatefulWidget {
  const ListingsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends State<ListingsScreen> {
  List<dynamic> _items = [];
  List<dynamic> _myRequests = [];
  String? _error;
  bool _loading = false;

  final _origin = TextEditingController(text: 'Paris');
  final _destination = TextEditingController(text: 'Lagos');
  final _maxWeight = TextEditingController(text: '5');
  final _pricePerKg = TextEditingController(text: '12');
  String _destinationType = 'city';

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
      _items = await widget.api.listTravelerListings();
      if (widget.api.role == 'client' || widget.api.role == 'admin') {
        _myRequests = await widget.api.myRequests();
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onListingTap(Map<String, dynamic> listing) async {
    if (!(widget.api.role == 'client' || widget.api.role == 'admin')) {
      return;
    }
    if (_myRequests.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Create a delivery request first, then tap a listing to start a match.')),
      );
      return;
    }

    String selectedRequestID = (_myRequests.first['id'] as String?) ?? '';
    final agreedPriceCtrl = TextEditingController(
      text: ((listing['price_per_kg'] as num?)?.toDouble() ?? 10)
          .toStringAsFixed(2),
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Delivery Match'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Traveler route: ${listing['origin']} -> ${listing['destination']}'),
            const SizedBox(height: 6),
            Text('Traveler: ${listing['traveler_name'] ?? 'Unknown'}'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedRequestID,
              items: _myRequests
                  .map((r) => DropdownMenuItem<String>(
                        value: (r['id'] as String?) ?? '',
                        child: Text('${r['origin']} -> ${r['destination']}'),
                      ))
                  .toList(),
              onChanged: (v) => selectedRequestID = v ?? '',
              decoration: const InputDecoration(labelText: 'Your Request'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: agreedPriceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Agreed Price (USD)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create Match')),
        ],
      ),
    );

    if (confirmed != true) {
      agreedPriceCtrl.dispose();
      return;
    }
    try {
      final agreedPrice = double.tryParse(agreedPriceCtrl.text.trim()) ?? 0;
      final estimatedDeliveryAt = (listing['arrival_date'] ?? '').toString();
      await widget.api.createMatch(
        listingID: (listing['id'] as String?) ?? '',
        requestID: selectedRequestID,
        agreedPrice: agreedPrice,
        estimatedDeliveryAt: estimatedDeliveryAt.isEmpty
            ? DateTime.now().toIso8601String()
            : estimatedDeliveryAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Match created. You can create escrow in My Work.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      agreedPriceCtrl.dispose();
    }
  }

  Future<void> _create() async {
    try {
      await widget.api.createTravelerListing({
        'origin': _origin.text.trim(),
        'destination_type': _destinationType,
        'destination': _destination.text.trim(),
        'departure_date': DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String(),
        'arrival_date': DateTime.now()
            .toUtc()
            .add(const Duration(days: 7, hours: 6))
            .toIso8601String(),
        'max_weight_kg': double.tryParse(_maxWeight.text) ?? 0,
        'price_per_kg': double.tryParse(_pricePerKg.text) ?? 0,
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
    final canCreateListing =
        widget.api.role == 'traveler' || widget.api.role == 'admin';
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canCreateListing) ...[
              const Text('Create Traveler Listing',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                  controller: _origin,
                  decoration: const InputDecoration(labelText: 'Origin')),
              const SizedBox(height: 8),
              TextField(
                  controller: _destination,
                  decoration: const InputDecoration(labelText: 'Destination')),
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
                  controller: _maxWeight,
                  decoration:
                      const InputDecoration(labelText: 'Max Weight (kg)')),
              const SizedBox(height: 8),
              TextField(
                  controller: _pricePerKg,
                  decoration: const InputDecoration(labelText: 'Price per kg')),
              const SizedBox(height: 10),
              FilledButton(
                  onPressed: _create, child: const Text('Publish Listing')),
              const Divider(height: 28),
            ] else ...[
              const Text(
                'Traveler listings are created by traveler accounts. As a client, use Requests tab to create your delivery request.',
              ),
              const Divider(height: 28),
            ],
            const Text('Available Listings',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ..._items.map((item) {
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: ((item['traveler_avatar_url'] ?? '').toString().isNotEmpty)
                        ? NetworkImage((item['traveler_avatar_url'] ?? '').toString())
                        : null,
                    child: ((item['traveler_avatar_url'] ?? '').toString().isEmpty)
                        ? Text(
                            ((item['traveler_name'] ?? 'T').toString().trim().isNotEmpty
                                    ? (item['traveler_name'] ?? 'T').toString().trim()[0]
                                    : 'T')
                                .toUpperCase(),
                          )
                        : null,
                  ),
                  title: Text('${item['origin']} -> ${item['destination']}'),
                  subtitle: Text(
                    'Traveler: ${item['traveler_name'] ?? 'Unknown'}\nType: ${item['destination_type']} | Weight: ${item['max_weight_kg']}kg | Price/kg: ${item['price_per_kg']}',
                  ),
                  onTap: widget.api.role == 'client' || widget.api.role == 'admin'
                      ? () => _onListingTap((item as Map).cast<String, dynamic>())
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
