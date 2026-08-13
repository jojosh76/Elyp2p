import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../widgets/responsive_page.dart';
import '../../widgets/fancy_card.dart';
import '../../widgets/animated_entry.dart';

class MyWorkScreen extends StatefulWidget {
  const MyWorkScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<MyWorkScreen> createState() => _MyWorkScreenState();
}

class _MyWorkScreenState extends State<MyWorkScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _availableListings = [];
  List<dynamic> _myListings = [];
  List<dynamic> _myRequests = [];
  List<dynamic> _openRequests = [];
  List<dynamic> _myMatches = [];
  List<dynamic> _myEscrows = [];
  List<dynamic> _myClaims = [];
  List<dynamic> _myReviews = [];
  bool _canReleaseSelectedEscrow = false;
  String _releaseHint = 'Select an escrow to check delivery status.';

  final _agreedPrice = TextEditingController(text: '25');
  final _escrowAmount = TextEditingController(text: '25');
  final _coverageLimit = TextEditingController(text: '50');
  final _claimReason = TextEditingController();
  final _claimAmount = TextEditingController(text: '50');
  final _reviewComment = TextEditingController();
  bool _insuranceEnabled = false;
  double _reviewRating = 5;
  String _selectedListingId = '';
  String _selectedRequestId = '';
  String _selectedMatchId = '';
  String _selectedEscrowId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _agreedPrice.dispose();
    _escrowAmount.dispose();
    _coverageLimit.dispose();
    _claimReason.dispose();
    _claimAmount.dispose();
    _reviewComment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _availableListings = await widget.api.listTravelerListings();
      _myListings = await widget.api.myListings();
      _myRequests = await widget.api.myRequests();
      _openRequests = await widget.api.listDeliveryRequests();
      _myMatches = await widget.api.myMatches();
      _myEscrows = await widget.api.myEscrows();
      _myClaims = await widget.api.myInsuranceClaims();
      _myReviews = await widget.api.myReviews();
      _selectedListingId =
          _pickFirstValid(_selectedListingId, _listingOptions());
      _selectedRequestId =
          _pickFirstValid(_selectedRequestId, _requestOptions());
      _selectedMatchId = _pickFirstValid(_selectedMatchId, _myMatches);
      _selectedEscrowId = _pickFirstValid(_selectedEscrowId, _myEscrows);
      await _refreshReleaseEligibility();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _claimStatusLabel(Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString();
    return status.isEmpty ? 'Pending' : status.replaceAll('_', ' ');
  }

  String _reviewSummary(Map<String, dynamic> item) {
    final rating = (item['rating'] ?? 0).toString();
    final comment = (item['comment'] ?? '').toString();
    return comment.isEmpty
        ? 'Rating: $rating/5'
        : 'Rating: $rating/5 — $comment';
  }

  Future<void> _refreshReleaseEligibility() async {
    if (_selectedEscrowId.isEmpty) {
      if (mounted) {
        setState(() {
          _canReleaseSelectedEscrow = false;
          _releaseHint = 'Select an escrow to check delivery status.';
        });
      }
      return;
    }
    final escrow =
        _myEscrows.cast<Map>().map((e) => e.cast<String, dynamic>()).firstWhere(
              (e) => (e['id'] ?? '').toString() == _selectedEscrowId,
              orElse: () => <String, dynamic>{},
            );
    final matchID = (escrow['match_id'] ?? '').toString();
    if (matchID.isEmpty) {
      if (mounted) {
        setState(() {
          _canReleaseSelectedEscrow = false;
          _releaseHint = 'Match not linked to this escrow yet.';
        });
      }
      return;
    }
    try {
      final events = await widget.api.listTracking(matchID);
      final delivered = events.any(
          (e) => (e['status'] ?? '').toString().toLowerCase() == 'delivered');
      if (!mounted) return;
      setState(() {
        _canReleaseSelectedEscrow = delivered;
        _releaseHint = delivered
            ? 'Delivery confirmed. You can release payment.'
            : 'Release is locked until tracking status is delivered.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canReleaseSelectedEscrow = false;
        _releaseHint = 'Could not verify delivery status yet.';
      });
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

  String _routeLabel(Map<String, dynamic> x) {
    final origin = (x['origin'] ?? '').toString();
    final destination = (x['destination'] ?? '').toString();
    if (origin.isEmpty && destination.isEmpty) return 'Saved request';
    if (origin.isEmpty) return 'To $destination';
    if (destination.isEmpty) return 'From $origin';
    return '$origin -> $destination';
  }

  List<dynamic> _requestOptions() {
    if (widget.api.role == 'traveler') return _openRequests;
    return _myRequests;
  }

  List<dynamic> _listingOptions() {
    if (widget.api.role == 'traveler') return _myListings;
    return _availableListings;
  }

  String _requestDropdownLabel() {
    return widget.api.role == 'traveler' ? 'Open Request' : 'Your Request';
  }

  String _listingDropdownLabel() {
    return widget.api.role == 'traveler' ? 'Your Listing' : 'Traveler Listing';
  }

  String _matchLabel(Map<String, dynamic> x) {
    final price = (x['agreed_price'] ?? 0).toString();
    final status = (x['status'] ?? '').toString();
    final parties = _matchPartiesLabel((x['id'] ?? '').toString());
    return 'Match: price $price | $status${parties.isEmpty ? '' : ' | $parties'}';
  }

  String _escrowLabel(Map<String, dynamic> x) {
    final amount = (x['amount'] ?? 0).toString();
    final currency = (x['currency'] ?? '').toString();
    final status = (x['status'] ?? '').toString();
    final payout = (x['payout_status'] ?? '').toString();
    return 'Escrow: $amount $currency | $status${payout.isEmpty ? '' : ' | payout=$payout'}';
  }

  Map<String, dynamic> _matchByID(String id) {
    return _myMatches
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .firstWhere((e) => (e['id'] ?? '').toString() == id,
            orElse: () => <String, dynamic>{});
  }

  Map<String, dynamic> _requestByID(String id) {
    final all = [..._myRequests, ..._openRequests];
    return all.cast<Map>().map((e) => e.cast<String, dynamic>()).firstWhere(
        (e) => (e['id'] ?? '').toString() == id,
        orElse: () => <String, dynamic>{});
  }

  Map<String, dynamic> _listingByID(String id) {
    final all = [..._myListings, ..._availableListings];
    return all.cast<Map>().map((e) => e.cast<String, dynamic>()).firstWhere(
        (e) => (e['id'] ?? '').toString() == id,
        orElse: () => <String, dynamic>{});
  }

  String _matchPartiesLabel(String matchID) {
    if (matchID.isEmpty) return '';
    final m = _matchByID(matchID);
    final req = _requestByID((m['request_id'] ?? '').toString());
    final lst = _listingByID((m['listing_id'] ?? '').toString());
    final client = (req['client_name'] ?? '').toString();
    final traveler = (lst['traveler_name'] ?? '').toString();
    if (client.isEmpty && traveler.isEmpty) return '';
    return 'client=$client traveler=$traveler'.trim();
  }

  Future<void> _deleteEscrow(String id) async {
    if (id.isEmpty) return;
    try {
      await widget.api.deleteEscrow(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
      }
    }
  }

  Future<void> _createMatch() async {
    try {
      if (_selectedListingId.isEmpty) {
        throw Exception('Select a listing');
      }
      if (_selectedRequestId.isEmpty) throw Exception('Select a request');
      final selectedListing = _listingOptions()
          .cast<Map>()
          .map((e) => e.cast<String, dynamic>())
          .firstWhere(
            (e) => (e['id'] ?? '').toString() == _selectedListingId,
            orElse: () => <String, dynamic>{},
          );
      final estimatedDeliveryAt =
          (selectedListing['arrival_date'] ?? '').toString();
      await widget.api.createMatch(
        listingID: _selectedListingId,
        requestID: _selectedRequestId,
        agreedPrice: double.tryParse(_agreedPrice.text) ?? 0,
        estimatedDeliveryAt: estimatedDeliveryAt.isEmpty
            ? DateTime.now().toIso8601String()
            : estimatedDeliveryAt,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
      }
    }
  }

  Future<void> _createEscrow() async {
    try {
      if (_selectedMatchId.isEmpty) throw Exception('Select a match first');
      await widget.api.createEscrow(
        matchID: _selectedMatchId,
        amount: double.tryParse(_escrowAmount.text) ?? 0,
        insuranceEnabled: _insuranceEnabled,
        coverageLimit: double.tryParse(_coverageLimit.text) ?? 0,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
      }
    }
  }

  Future<void> _submitClaim() async {
    try {
      if (_selectedEscrowId.isEmpty) {
        throw Exception('Select a protected escrow');
      }
      final reason = _claimReason.text.trim();
      final amount = double.tryParse(_claimAmount.text) ?? 0;
      if (reason.isEmpty) {
        throw Exception('Describe the loss or incident before submitting');
      }
      if (amount <= 0) {
        throw Exception('Requested amount must be greater than zero');
      }
      await widget.api.createInsuranceClaim(
        escrowID: _selectedEscrowId,
        reason: reason,
        requestedAmount: amount,
      );
      _claimReason.clear();
      _claimAmount.text = '50';
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

  Future<void> _submitReview() async {
    try {
      if (_selectedMatchId.isEmpty) {
        throw Exception('Select a completed match');
      }
      await widget.api.createReview(
        matchID: _selectedMatchId,
        rating: _reviewRating.round(),
        comment: _reviewComment.text.trim(),
      );
      _reviewComment.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your rating')),
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

  Future<void> _fundEscrow() async {
    try {
      if (_selectedEscrowId.isEmpty) throw Exception('Select an escrow');
      await widget.api.fundEscrow(_selectedEscrowId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
      }
    }
  }

  Future<void> _releaseEscrow() async {
    try {
      if (_selectedEscrowId.isEmpty) throw Exception('Select an escrow');
      if (!_canReleaseSelectedEscrow) {
        throw Exception(
            'Release is allowed only after delivery is marked as delivered');
      }
      await widget.api.releaseEscrow(_selectedEscrowId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
      }
    }
  }

  Future<void> _refundEscrow() async {
    try {
      if (_selectedEscrowId.isEmpty) throw Exception('Select an escrow');
      await widget.api.refundEscrow(_selectedEscrowId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
      }
    }
  }

  Future<void> _disputeEscrow() async {
    try {
      if (_selectedEscrowId.isEmpty) throw Exception('Select an escrow');
      await widget.api.disputeEscrow(_selectedEscrowId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreateMatch =
        widget.api.role == 'traveler' || widget.api.role == 'client';
    final canManagePayments =
        widget.api.role == 'client' || widget.api.role == 'admin';
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsivePage(
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  onSurface: Colors.white,
                  onSurfaceVariant: Colors.white.withValues(alpha: 0.75),
                ),
            inputDecorationTheme:
                Theme.of(context).inputDecorationTheme.copyWith(
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintStyle: const TextStyle(color: Colors.white60),
                    ),
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('My Work',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 4),
              const Text(
                  'Manage matching and payment steps using selections instead of IDs.'),
              const SizedBox(height: 12),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (canCreateMatch)
                FancyCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('1) Create Match',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (_requestOptions().isEmpty)
                          const Text('No requests available yet.')
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRequestId.isEmpty
                                ? null
                                : _selectedRequestId,
                            items: _requestOptions()
                                .map((e) => (e as Map).cast<String, dynamic>())
                                .map((e) => DropdownMenuItem<String>(
                                      value: (e['id'] ?? '').toString(),
                                      child: Text(_routeLabel(e)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedRequestId = v ?? ''),
                            decoration: InputDecoration(
                                labelText: _requestDropdownLabel()),
                          ),
                        const SizedBox(height: 8),
                        if (_listingOptions().isEmpty)
                          const Text('No listings available yet.')
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _selectedListingId.isEmpty
                                ? null
                                : _selectedListingId,
                            items: _listingOptions()
                                .map((e) => (e as Map).cast<String, dynamic>())
                                .map((e) => DropdownMenuItem<String>(
                                      value: (e['id'] ?? '').toString(),
                                      child: Text(_routeLabel(e)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedListingId = v ?? ''),
                            decoration: InputDecoration(
                                labelText: _listingDropdownLabel()),
                          ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _agreedPrice,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Agreed Price'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Loss coverage'),
                          subtitle: const Text(
                              '2% premium of the coverage limit; claims are reviewed by the team.'),
                          value: _insuranceEnabled,
                          onChanged: (v) =>
                              setState(() => _insuranceEnabled = v),
                        ),
                        if (_insuranceEnabled)
                          TextField(
                              controller: _coverageLimit,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Coverage limit')),
                        const SizedBox(height: 8),
                        FilledButton(
                            onPressed: _createMatch,
                            child: const Text('Create Match')),
                      ],
                    ),
                  ),
                ),
              if (canManagePayments)
                FancyCard(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Loss coverage claim',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              const Text(
                                  'Select a covered escrow above, then describe the loss or damage.'),
                              TextField(
                                  controller: _claimReason,
                                  decoration: const InputDecoration(
                                      labelText: 'What happened?')),
                              TextField(
                                  controller: _claimAmount,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Requested amount')),
                              const SizedBox(height: 8),
                              FilledButton.tonal(
                                  onPressed: _submitClaim,
                                  child: const Text('Submit claim')),
                            ]))),
              FancyCard(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Rate your delivery partner',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const Text(
                                'Available once the escrow has been released.'),
                            Slider(
                                value: _reviewRating,
                                min: 1,
                                max: 5,
                                divisions: 4,
                                label: '${_reviewRating.round()} / 5',
                                onChanged: (v) =>
                                    setState(() => _reviewRating = v)),
                            TextField(
                                controller: _reviewComment,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                    labelText: 'Comment (optional)')),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                                onPressed: _submitReview,
                                child: const Text('Publish rating')),
                          ]))),
              if (canManagePayments)
                FancyCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('2) Create Escrow',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedMatchId.isEmpty
                              ? null
                              : _selectedMatchId,
                          items: _myMatches
                              .map((e) => (e as Map).cast<String, dynamic>())
                              .map((e) => DropdownMenuItem<String>(
                                    value: (e['id'] ?? '').toString(),
                                    child: Text(_matchLabel(e)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedMatchId = v ?? ''),
                          decoration: const InputDecoration(labelText: 'Match'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _escrowAmount,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Escrow Amount'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                            onPressed: _createEscrow,
                            child: const Text('Create Escrow')),
                      ],
                    ),
                  ),
                ),
              if (canManagePayments)
                FancyCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('3) Fund or Release Escrow',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedEscrowId.isEmpty
                              ? null
                              : _selectedEscrowId,
                          items: _myEscrows
                              .map((e) => (e as Map).cast<String, dynamic>())
                              .map((e) => DropdownMenuItem<String>(
                                    value: (e['id'] ?? '').toString(),
                                    child: Text(_escrowLabel(e)),
                                  ))
                              .toList(),
                          onChanged: (v) async {
                            setState(() => _selectedEscrowId = v ?? '');
                            await _refreshReleaseEligibility();
                          },
                          decoration:
                              const InputDecoration(labelText: 'Escrow'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _releaseHint,
                          style: TextStyle(
                            color: _canReleaseSelectedEscrow
                                ? Colors.green.shade700
                                : Colors.orange.shade800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _selectedEscrowId.isEmpty
                                ? null
                                : _refreshReleaseEligibility,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh delivery status'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                                onPressed: _fundEscrow,
                                child: const Text('Fund')),
                            OutlinedButton(
                                onPressed: _disputeEscrow,
                                child: const Text('Dispute')),
                            OutlinedButton(
                                onPressed: _refundEscrow,
                                child: const Text('Refund')),
                            if (_canReleaseSelectedEscrow)
                              OutlinedButton(
                                  onPressed: _releaseEscrow,
                                  child: const Text('Release')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Text('My Insurance Claims',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (_myClaims.isEmpty)
                const Text('No insurance claims yet.')
              else
                ..._myClaims.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = (entry.value as Map).cast<String, dynamic>();
                  return AnimatedEntry(
                    delay: Duration(milliseconds: 80 * i),
                    child: FancyCard(
                      child: ListTile(
                        title: Text('Claim for ${item['escrow_id'] ?? ''}'),
                        subtitle: Text(
                          'Status: ${_claimStatusLabel(item)}\n'
                          'Requested amount: ${item['requested_amount'] ?? 0}\n'
                          '${item['reason'] ?? ''}',
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              const Text('My Reviews',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (_myReviews.isEmpty)
                const Text('No reviews published yet.')
              else
                ..._myReviews.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = (entry.value as Map).cast<String, dynamic>();
                  return AnimatedEntry(
                    delay: Duration(milliseconds: 90 * i),
                    child: FancyCard(
                      child: ListTile(
                        title: Text('Match ${item['match_id'] ?? ''}'),
                        subtitle: Text(_reviewSummary(item)),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              const Text('My Requests',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ..._myRequests.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final x = (e as Map).cast<String, dynamic>();
                return AnimatedEntry(
                  delay: Duration(milliseconds: 50 * i),
                  child: FancyCard(
                    child: ListTile(
                      title: Text(_routeLabel(x)),
                      subtitle: Text(
                          'Status ${x['status'] ?? ''} | ${x['weight_kg'] ?? 0} kg'),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              const Text('My Matches',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ..._myMatches.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final x = (e as Map).cast<String, dynamic>();
                final eta = (x['estimated_delivery_at'] ?? '').toString();
                return AnimatedEntry(
                  delay: Duration(milliseconds: 60 * i),
                  child: FancyCard(
                    child: ListTile(
                      title: Text('Agreed Price ${x['agreed_price'] ?? 0}'),
                      subtitle: Text(
                        eta.isEmpty
                            ? 'Status ${x['status'] ?? ''}'
                            : 'Status ${x['status'] ?? ''} | ETA $eta',
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              const Text('My Escrows',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ..._myEscrows.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final x = (e as Map).cast<String, dynamic>();
                final matchID = (x['match_id'] ?? '').toString();
                final parties = _matchPartiesLabel(matchID);
                final payout = (x['payout_status'] ?? '').toString();
                return AnimatedEntry(
                  delay: Duration(milliseconds: 70 * i),
                  child: FancyCard(
                    child: ListTile(
                      title: Text('${x['amount'] ?? 0} ${x['currency'] ?? ''}'),
                      subtitle: Text(
                          'Status ${x['status'] ?? ''} | Commission ${x['commission_amount'] ?? 0}${payout.isEmpty ? '' : ' | payout $payout'}${parties.isEmpty ? '' : '\n$parties'}'),
                      trailing: IconButton(
                        tooltip: 'Delete escrow',
                        onPressed: () =>
                            _deleteEscrow((x['id'] ?? '').toString()),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
