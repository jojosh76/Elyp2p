import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../widgets/animated_entry.dart';
import '../../widgets/fancy_card.dart';
import '../../widgets/responsive_page.dart';

class InsuranceScreen extends StatefulWidget {
  const InsuranceScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _myEscrows = [];
  List<dynamic> _claims = [];

  final _reason = TextEditingController();
  final _amount = TextEditingController(text: '50');
  String _selectedEscrowId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _myEscrows = await widget.api.myEscrows();
      _claims = await widget.api.myInsuranceClaims();
      _selectedEscrowId = _pickFirstValid(_selectedEscrowId, _myEscrows);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _pickFirstValid(String current, List<dynamic> rows) {
    if (rows.isEmpty) return '';
    final ids = rows
        .map((e) => (e['id'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (ids.contains(current)) return current;
    return ids.first;
  }

  String _escrowLabel(Map<String, dynamic> item) {
    final amount = (item['amount'] ?? 0).toString();
    final currency = (item['currency'] ?? '').toString();
    final status = (item['status'] ?? '').toString();
    return 'Escrow $amount $currency — $status';
  }

  String _statusLabel(Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString();
    return status.isEmpty ? 'pending' : status.replaceAll('_', ' ');
  }

  Future<void> _submit() async {
    try {
      if (_selectedEscrowId.isEmpty) {
        throw Exception('Select an escrow');
      }
      final reason = _reason.text.trim();
      final amount = double.tryParse(_amount.text) ?? 0;
      if (reason.isEmpty) {
        throw Exception('Describe the loss before submitting the claim');
      }
      if (amount <= 0) {
        throw Exception('Requested amount must be greater than zero');
      }
      await widget.api.createInsuranceClaim(
        escrowID: _selectedEscrowId,
        reason: reason,
        requestedAmount: amount,
      );
      _reason.clear();
      _amount.text = '50';
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insurance claim submitted for review')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
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
            const Text(
              'Insurance',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Submit a loss claim and track insurance coverage linked to a protected escrow.',
            ),
            const SizedBox(height: 16),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            FancyCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Declare a claim',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    if (_myEscrows.isEmpty)
                      const Text('No protected escrow available yet.')
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _selectedEscrowId.isEmpty
                            ? null
                            : _selectedEscrowId,
                        items: _myEscrows
                            .map((e) => (e as Map).cast<String, dynamic>())
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: (e['id'] ?? '').toString(),
                                child: Text(_escrowLabel(e)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedEscrowId = value ?? ''),
                        decoration: const InputDecoration(labelText: 'Escrow'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reason,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'What happened?',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Requested amount',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Submit claim'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'My claims',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_claims.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No insurance claims yet.'),
              )
            else
              ..._claims.asMap().entries.map((entry) {
                final i = entry.key;
                final item = (entry.value as Map).cast<String, dynamic>();
                return AnimatedEntry(
                  delay: Duration(milliseconds: 50 * i),
                  child: FancyCard(
                    child: ListTile(
                      title: Text('Claim ${item['id'] ?? ''}'),
                      subtitle: Text(
                        'Status: ${_statusLabel(item)}\n'
                        'Escrow: ${item['escrow_id'] ?? ''}\n'
                        'Requested: ${item['requested_amount'] ?? 0}\n'
                        '${item['reason'] ?? ''}',
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
