import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../widgets/animated_entry.dart';
import '../../widgets/fancy_card.dart';
import '../../widgets/responsive_page.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _myMatches = [];
  List<dynamic> _myReviews = [];

  final _comment = TextEditingController();
  double _rating = 5;
  String _selectedMatchId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _myMatches = await widget.api.myMatches();
      _myReviews = await widget.api.myReviews();
      _selectedMatchId = _pickFirstValid(_selectedMatchId, _myMatches);
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

  String _matchLabel(Map<String, dynamic> item) {
    final price = (item['agreed_price'] ?? 0).toString();
    final status = (item['status'] ?? '').toString();
    return 'Match $price — $status';
  }

  String _reviewSummary(Map<String, dynamic> item) {
    final rating = (item['rating'] ?? 0).toString();
    final comment = (item['comment'] ?? '').toString();
    return comment.isEmpty
        ? 'Rating: $rating/5'
        : 'Rating: $rating/5 — $comment';
  }

  Future<void> _submit() async {
    try {
      if (_selectedMatchId.isEmpty) {
        throw Exception('Select a completed match');
      }
      await widget.api.createReview(
        matchID: _selectedMatchId,
        rating: _rating.round(),
        comment: _comment.text.trim(),
      );
      _comment.clear();
      _rating = 5;
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Reviews',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rate the people you completed a delivery with and build trust in the community.',
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
                      'Leave a rating',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    if (_myMatches.isEmpty)
                      const Text('No completed match available yet.')
                    else
                      DropdownButtonFormField<String>(
                        initialValue:
                            _selectedMatchId.isEmpty ? null : _selectedMatchId,
                        items: _myMatches
                            .map((e) => (e as Map).cast<String, dynamic>())
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: (e['id'] ?? '').toString(),
                                child: Text(_matchLabel(e)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedMatchId = value ?? ''),
                        decoration: const InputDecoration(labelText: 'Match'),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Rating: '),
                        Expanded(
                          child: Slider(
                            value: _rating,
                            min: 1,
                            max: 5,
                            divisions: 4,
                            label: '${_rating.round()} / 5',
                            onChanged: (value) =>
                                setState(() => _rating = value),
                          ),
                        ),
                        Text('${_rating.round()} / 5'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _comment,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Comment (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.star_outline_rounded),
                      label: const Text('Publish rating'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'My ratings',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_myReviews.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No reviews published yet.'),
              )
            else
              ..._myReviews.asMap().entries.map((entry) {
                final i = entry.key;
                final item = (entry.value as Map).cast<String, dynamic>();
                return AnimatedEntry(
                  delay: Duration(milliseconds: 50 * i),
                  child: FancyCard(
                    child: ListTile(
                      title: Text('Match ${item['match_id'] ?? ''}'),
                      subtitle: Text(_reviewSummary(item)),
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
