import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  ApiClient({required this.baseUrl, this.demoMode = false}) {
    _seed();
  }

  final String baseUrl;
  final bool demoMode;
  bool _forcedDemo = false;
  bool get _demo => demoMode || _forcedDemo;

  String? token;
  Map<String, dynamic>? currentUser;
  static const _sessionTokenKey = 'session_token';
  static const _sessionUserKey = 'session_user';
  String get role => (currentUser?['role'] as String?) ?? 'client';

  final List<Map<String, dynamic>> _listings = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _requests = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _matches = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _escrows = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _kyc = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _pkg = <Map<String, dynamic>>[];
  final Map<String, List<Map<String, dynamic>>> _tracking =
      <String, List<Map<String, dynamic>>>{};
  final List<Map<String, dynamic>> _notifications = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _providers = <Map<String, dynamic>>[
    {
      'provider': 'google',
      'enabled': true,
      'client_id': '',
      'ios_client_id': '',
      'web_client_id': ''
    },
    {
      'provider': 'apple',
      'enabled': true,
      'client_id': '',
      'ios_client_id': '',
      'web_client_id': ''
    },
  ];
  int _id = 3000;

  void _seed() {
    if (_notifications.isNotEmpty ||
        _listings.isNotEmpty ||
        _requests.isNotEmpty) {
      return;
    }
  }

  String _next(String p) => '$p${++_id}';
  bool _isNetErr(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('connection refused') ||
        s.contains('failed host lookup') ||
        s.contains('timed out') ||
        s.contains('network is unreachable');
  }

  void setAuthPayload(Map<String, dynamic> payload) {
    token = payload['token'] as String?;
    currentUser = payload['user'] as Map<String, dynamic>?;
  }

  Future<void> persistSession() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_sessionTokenKey, token ?? '');
    await p.setString(
        _sessionUserKey, jsonEncode(currentUser ?? <String, dynamic>{}));
  }

  Future<void> restoreSession() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_sessionTokenKey) ?? '';
    final u = p.getString(_sessionUserKey) ?? '{}';
    token = t.isEmpty ? null : t;
    try {
      currentUser = (jsonDecode(u) as Map).cast<String, dynamic>();
    } catch (_) {
      currentUser = null;
    }
  }

  Future<void> clearSession() async {
    token = null;
    currentUser = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_sessionTokenKey);
    await p.remove(_sessionUserKey);
  }

  Map<String, String> _headers({bool auth = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth && token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Future<dynamic> _call(String method, String path,
      {bool auth = false,
      Map<String, dynamic>? body,
      Map<String, String>? query,
      bool list = false}) async {
    if (_demo) {
      return _demoCall(method, path, body: body, query: query, list: list);
    }
    final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: query == null || query.isEmpty ? null : query);
    try {
      http.Response r;
      if (method == 'GET') {
        r = await http.get(uri, headers: _headers(auth: auth));
      } else if (method == 'POST') {
        r = await http.post(uri,
            headers: _headers(auth: auth),
            body: body == null ? null : jsonEncode(body));
      } else if (method == 'PUT') {
        r = await http.put(uri,
            headers: _headers(auth: auth),
            body: body == null ? null : jsonEncode(body));
      } else {
        r = await http.delete(uri, headers: _headers(auth: auth));
      }
      if (r.statusCode >= 400) {
        final m = jsonDecode(r.body) as Map<String, dynamic>;
        throw Exception(m['error'] ?? 'Request failed');
      }
      return list
          ? (jsonDecode(r.body) as List<dynamic>)
          : (jsonDecode(r.body) as Map<String, dynamic>);
    } catch (e) {
      if (_isNetErr(e)) {
        _forcedDemo = true;
        return _demoCall(method, path, body: body, query: query, list: list);
      }
      rethrow;
    }
  }

  Map<String, dynamic> _userOrThrow() {
    if (currentUser == null || token == null || token!.isEmpty) {
      throw Exception('Please sign in first');
    }
    return currentUser!;
  }

  Map<String, dynamic> _mkUser(
    String role,
    String email,
    String fullName, {
    String phone = '',
    String permanentAddress = '',
    String passportNumber = '',
    String countryOfResidence = 'US',
  }) =>
      {
        'id': _next('u_'),
        'email': email,
        'full_name': fullName,
        'role': (role == 'admin' || role == 'traveler') ? role : 'client',
        'phone': phone,
        'bio': '',
        'avatar_url': '',
        'permanent_address': permanentAddress,
        'country_of_residence': countryOfResidence,
        'passport_number': passportNumber,
        'kyc_status': role == 'traveler' ? 'pending' : 'not_required',
      };

  dynamic _demoCall(String method, String path,
      {Map<String, dynamic>? body,
      Map<String, String>? query,
      required bool list}) {
    if (path == '/healthz') return <String, dynamic>{'status': 'ok'};
    if (path == '/v1/auth/providers') return _providers;
    if (path == '/v1/auth/register' ||
        path == '/v1/auth/login' ||
        path == '/v1/auth/otp/verify' ||
        path == '/v1/auth/social') {
      final email = (body?['email'] ?? 'demo@local.dev').toString();
      final fn = (body?['full_name'] ?? 'Demo User').toString();
      if (path == '/v1/auth/register' &&
          (body?['role'] ?? 'client').toString() == 'admin') {
        throw Exception('admin accounts must be created by an existing administrator');
      }
      final inferred = path == '/v1/auth/register'
          ? (body?['role'] ?? 'client').toString()
          : email.toLowerCase().contains('admin')
              ? 'admin'
              : (email.toLowerCase().contains('travel')
                  ? 'traveler'
                  : ((body?['role'] ?? 'client').toString()));
      final u = _mkUser(
        inferred,
        email,
        fn,
        phone: (body?['phone'] ?? '').toString(),
        permanentAddress: (body?['permanent_address'] ?? '').toString(),
        passportNumber: (body?['passport_number'] ?? '').toString(),
        countryOfResidence:
            (body?['country_of_residence'] ?? 'US').toString(),
      );
      token = 'demo-token-${DateTime.now().millisecondsSinceEpoch}';
      currentUser = u;
      return <String, dynamic>{
        'token': token,
        'user': u,
        'otp_required': false
      };
    }
    if (path == '/v1/me' && method == 'GET') return _userOrThrow();
    if (path == '/v1/me' && method == 'DELETE') {
      token = null;
      currentUser = null;
      return <String, dynamic>{'ok': true};
    }
    if (path == '/v1/auth/logout' && method == 'POST') {
      token = null;
      currentUser = null;
      return <String, dynamic>{'status': 'logged_out'};
    }
    if (path == '/v1/me/profile' && method == 'GET') return _userOrThrow();
    if (path == '/v1/me/profile' && method == 'PUT') {
      final me = _userOrThrow();
      me.addAll(body ?? <String, dynamic>{});
      currentUser = me;
      return me;
    }
    if (path == '/v1/travelers/listings' && method == 'GET') {
      return query?['destination'] == null
          ? List<dynamic>.from(_listings)
          : _listings
              .where((e) => (e['destination']?.toString().toLowerCase() ?? '')
                  .contains(query!['destination']!.toLowerCase()))
              .toList();
    }
    if (path == '/v1/clients/requests' && method == 'GET') {
      final me = currentUser;
      final role = (me?['role'] ?? 'client').toString();
      final all = query?['destination'] == null
          ? List<Map<String, dynamic>>.from(_requests)
          : _requests
              .where((e) => (e['destination']?.toString().toLowerCase() ?? '')
                  .contains(query!['destination']!.toLowerCase()))
              .toList();
      if (role == 'client') {
        final uid = (me?['id'] ?? '').toString();
        return all
            .where((e) => (e['user_id'] ?? '').toString() == uid)
            .toList();
      }
      return all;
    }
    if (path == '/v1/travelers/listings' && method == 'POST') {
      final me = _userOrThrow();
      final x = <String, dynamic>{
        ...(body ?? <String, dynamic>{}),
        'id': _next('lst_'),
        'user_id': me['id'],
        'traveler_id': me['id'],
        'traveler_name': me['full_name'] ?? '',
        'traveler_avatar_url': me['avatar_url'] ?? '',
      };
      _listings.insert(0, x);
      return x;
    }
    if (path == '/v1/clients/requests' && method == 'POST') {
      final me = _userOrThrow();
      final x = <String, dynamic>{
        ...(body ?? <String, dynamic>{}),
        'id': _next('req_'),
        'user_id': me['id'],
        'client_id': me['id'],
        'client_name': me['full_name'] ?? '',
        'client_avatar_url': me['avatar_url'] ?? '',
      };
      _requests.insert(0, x);
      return x;
    }
    if (path == '/v1/me/listings') {
      return _listings
          .where((e) => e['user_id'] == _userOrThrow()['id'])
          .toList();
    }
    if (path == '/v1/me/requests') {
      return _requests
          .where((e) => e['user_id'] == _userOrThrow()['id'])
          .toList();
    }
    if (path == '/v1/me/matches') return List<dynamic>.from(_matches);
    if (path == '/v1/me/escrows') return List<dynamic>.from(_escrows);
    if (path.startsWith('/v1/me/escrows/') && method == 'DELETE') {
      final id = path.split('/').last;
      _escrows.removeWhere((e) => (e['id'] ?? '').toString() == id);
      return <String, dynamic>{'deleted': true};
    }
    if (path == '/v1/matches') {
      final x = <String, dynamic>{
        'id': _next('mat_'),
        'listing_id': body?['listing_id'],
        'request_id': body?['request_id'],
        'agreed_price': body?['agreed_price'],
        'estimated_delivery_at': body?['estimated_delivery_at'],
        'status': 'matched',
      };
      _matches.insert(0, x);
      return x;
    }
    if (path == '/v1/escrows') {
      final amt = (body?['amount'] as num?)?.toDouble() ?? 0;
      final x = <String, dynamic>{
        'id': _next('esc_'),
        'match_id': body?['match_id'],
        'amount': amt,
        'currency': body?['currency'] ?? 'USD',
        'status': 'created',
        'commission_amount': amt * 0.1
      };
      _escrows.insert(0, x);
      return x;
    }
    if (path.startsWith('/v1/escrows/') && path.endsWith('/fund')) {
      final id = path.split('/')[3];
      final x = _escrows.firstWhere((e) => e['id'] == id,
          orElse: () => <String, dynamic>{
                'id': id,
                'amount': 0,
                'currency': 'USD',
                'commission_amount': 0
              });
      x['status'] = 'funded';
      return x;
    }
    if (path.startsWith('/v1/escrows/') && path.endsWith('/release')) {
      final id = path.split('/')[3];
      final x = _escrows.firstWhere((e) => e['id'] == id,
          orElse: () => <String, dynamic>{
                'id': id,
                'amount': 0,
                'currency': 'USD',
                'commission_amount': 0
              });
      x['status'] = 'released';
      return x;
    }
    if (path.startsWith('/v1/escrows/') && path.endsWith('/refund')) {
      final id = path.split('/')[3];
      final x = _escrows.firstWhere((e) => e['id'] == id,
          orElse: () => <String, dynamic>{
                'id': id,
                'amount': 0,
                'currency': 'USD',
                'commission_amount': 0
              });
      x['status'] = 'refunded';
      return x;
    }
    if (path.startsWith('/v1/escrows/') && path.endsWith('/dispute')) {
      final id = path.split('/')[3];
      final x = _escrows.firstWhere((e) => e['id'] == id,
          orElse: () => <String, dynamic>{
                'id': id,
                'amount': 0,
                'currency': 'USD',
                'commission_amount': 0
              });
      x['status'] = 'disputed';
      return x;
    }
    if (path == '/v1/kyc/verifications' && method == 'POST') {
      final me = _userOrThrow();
      final x = <String, dynamic>{
        'id': _next('kyc_'),
        'user_id': me['id'],
        'document_type': body?['document_type'],
        'document_reference': body?['document_reference'],
        'address_proof_ref': body?['address_proof_ref'],
        'status': 'pending',
        'review_notes': ''
      };
      _kyc.insert(0, x);
      me['kyc_status'] = 'pending';
      return x;
    }
    if (path == '/v1/me/kyc/verifications') {
      return _kyc
          .where((e) =>
              e['user_id'] == _userOrThrow()['id'] &&
              (query?['status'] == null || e['status'] == query!['status']))
          .toList();
    }
    if (path == '/v1/packages/verifications' && method == 'POST') {
      final me = _userOrThrow();
      final risk = (body?['risk_score'] as num?)?.toInt() ?? 0;
      final x = <String, dynamic>{
        'id': _next('pkg_'),
        'user_id': me['id'],
        'request_id': body?['request_id'],
        'declared_contents': body?['declared_contents'],
        'receipt_ref': body?['receipt_ref'],
        'screening_method': body?['screening_method'],
        'risk_score': risk,
        'status': risk > 75 ? 'rejected_high_risk' : 'approved'
      };
      _pkg.insert(0, x);
      return x;
    }
    if (path == '/v1/me/packages/verifications') {
      return _pkg
          .where((e) =>
              e['user_id'] == _userOrThrow()['id'] &&
              (query?['status'] == null || e['status'] == query!['status']))
          .toList();
    }
    if (path == '/v1/tracking/events') {
      final m = (body?['match_id'] ?? '').toString();
      if (m.isEmpty) throw Exception('match_id is required');
      final x = <String, dynamic>{
        'id': _next('trk_'),
        'match_id': m,
        'status': body?['status'] ?? 'in_transit',
        'location': body?['location'] ?? '',
        'notes': body?['notes'] ?? '',
        'occurred_at': body?['occurred_at'] ?? DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      };
      _tracking.putIfAbsent(m, () => <Map<String, dynamic>>[]).insert(0, x);
      return x;
    }
    if (path.startsWith('/v1/tracking/')) {
      return List<dynamic>.from(_tracking[path.split('/').last] ?? const []);
    }
    if (path == '/v1/admin/users') {
      return <dynamic>[
        _userOrThrow(),
        _mkUser('traveler', 'traveler@demo.local', 'Demo Traveler'),
        _mkUser('client', 'client@demo.local', 'Demo Client')
      ];
    }
    if (path == '/v1/admin/escrows') return List<dynamic>.from(_escrows);
    if (path == '/v1/admin/commissions/summary') {
      final rel = _escrows.where((e) => e['status'] == 'released');
      final vol = rel.fold<double>(
          0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
      final com = rel.fold<double>(
          0, (s, e) => s + ((e['commission_amount'] as num?)?.toDouble() ?? 0));
      return <String, dynamic>{
        'released_escrows': rel.length,
        'total_volume': vol,
        'total_commission': com
      };
    }
    if (path == '/v1/admin/kyc/verifications') {
      return query?['status'] == null
          ? List<dynamic>.from(_kyc)
          : _kyc.where((e) => e['status'] == query!['status']).toList();
    }
    if (path.startsWith('/v1/admin/kyc/verifications/') &&
        path.endsWith('/review')) {
      final id = path.split('/')[5];
      final r = _kyc.firstWhere((e) => e['id'] == id,
          orElse: () => <String, dynamic>{'id': id});
      r['status'] = body?['status'];
      r['review_notes'] = body?['notes'] ?? '';
      return r;
    }
    if (path == '/v1/admin/packages/verifications') {
      return query?['status'] == null
          ? List<dynamic>.from(_pkg)
          : _pkg.where((e) => e['status'] == query!['status']).toList();
    }
    if (path.startsWith('/v1/admin/packages/verifications/') &&
        path.endsWith('/review')) {
      final id = path.split('/')[5];
      final r = _pkg.firstWhere((e) => e['id'] == id,
          orElse: () => <String, dynamic>{'id': id});
      r['status'] = body?['status'];
      r['review_notes'] = body?['notes'] ?? '';
      return r;
    }
    if (path == '/v1/admin/oauth/providers' && method == 'GET') {
      return _providers;
    }
    if (path.startsWith('/v1/admin/oauth/providers/') && method == 'PUT') {
      final provider = path.split('/').last;
      final row = <String, dynamic>{
        'provider': provider,
        'enabled': body?['enabled'] ?? true,
        'client_id': body?['client_id'] ?? '',
        'ios_client_id': body?['ios_client_id'] ?? '',
        'web_client_id': body?['web_client_id'] ?? ''
      };
      final i = _providers.indexWhere((e) => e['provider'] == provider);
      if (i >= 0) {
        _providers[i] = row;
      } else {
        _providers.add(row);
      }
      return row;
    }
    if (path == '/v1/me/notifications') {
      return List<dynamic>.from(_notifications);
    }
    if (path == '/v1/me/notifications/unread-count') {
      final unread = _notifications
          .where((e) => (e['read_at'] ?? '').toString().isEmpty)
          .length;
      return <String, dynamic>{'unread_count': unread};
    }
    if (path.startsWith('/v1/me/notifications/') && path.endsWith('/read')) {
      final id = path.split('/')[4];
      final r = _notifications.firstWhere((e) => e['id'] == id,
          orElse: () => <String, dynamic>{'id': id});
      r['read_at'] = DateTime.now().toIso8601String();
      return r;
    }
    if (path.startsWith('/v1/me/notifications/') && method == 'DELETE') {
      final id = path.split('/').last;
      _notifications.removeWhere((e) => (e['id'] ?? '').toString() == id);
      return <String, dynamic>{'deleted': true};
    }
    throw Exception('Demo route not implemented: $method $path');
  }

  Future<Map<String, dynamic>> register(
      {required String email,
      required String password,
      required String fullName,
      required String role,
      String phone = '',
      String permanentAddress = '',
      String passportNumber = '',
      String countryOfResidence = ''}) async {
    final out = (await _call('POST', '/v1/auth/register', body: {
      'email': email,
      'password': password,
      'full_name': fullName,
      'role': role,
      'phone': phone,
      'permanent_address': permanentAddress,
      'passport_number': passportNumber,
      'country_of_residence': countryOfResidence
    })) as Map<String, dynamic>;
    setAuthPayload(out);
    await persistSession();
    return out;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final out = (await _call('POST', '/v1/auth/login',
        body: {'email': email, 'password': password})) as Map<String, dynamic>;
    setAuthPayload(out);
    await persistSession();
    return out;
  }

  Future<Map<String, dynamic>> verifyOtp(
      {required String otpSessionID, required String otpCode}) async {
    final out = (await _call('POST', '/v1/auth/otp/verify',
            body: {'otp_session_id': otpSessionID, 'otp_code': otpCode}))
        as Map<String, dynamic>;
    setAuthPayload(out);
    await persistSession();
    return out;
  }

  Future<Map<String, dynamic>> socialLogin(
      {required String provider,
      String accessToken = '',
      String idToken = '',
      String email = '',
      String fullName = ''}) async {
    final out = (await _call('POST', '/v1/auth/social', body: {
      'provider': provider,
      'access_token': accessToken,
      'id_token': idToken,
      'email': email,
      'full_name': fullName
    })) as Map<String, dynamic>;
    setAuthPayload(out);
    await persistSession();
    return out;
  }

  Future<List<dynamic>> authProviders() async =>
      (await _call('GET', '/v1/auth/providers', list: true)) as List<dynamic>;
  Future<Map<String, dynamic>> me() async =>
      (await _call('GET', '/v1/me', auth: true)) as Map<String, dynamic>;
  Future<void> deleteMe() async {
    await _call('DELETE', '/v1/me', auth: true);
    token = null;
    currentUser = null;
    await persistSession();
  }

  Future<void> logout() async {
    try {
      await _call('POST', '/v1/auth/logout', auth: true);
    } finally {
      token = null;
      currentUser = null;
      await persistSession();
    }
  }

  Future<bool> healthz() async {
    try {
      await _call('GET', '/healthz');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> profile() async {
    final out = (await _call('GET', '/v1/me/profile', auth: true))
        as Map<String, dynamic>;
    currentUser = <String, dynamic>{...?currentUser, ...out};
    await persistSession();
    return out;
  }
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async {
    final out = (await _call('PUT', '/v1/me/profile', auth: true, body: body))
        as Map<String, dynamic>;
    currentUser = <String, dynamic>{...?currentUser, ...out};
    await persistSession();
    return out;
  }
  Future<List<dynamic>> listTravelerListings({String? destination}) async =>
      (await _call('GET', '/v1/travelers/listings',
          query: destination == null || destination.isEmpty
              ? null
              : {'destination': destination},
          list: true)) as List<dynamic>;
  Future<List<dynamic>> listDeliveryRequests({String? destination}) async =>
      (await _call('GET', '/v1/clients/requests',
          auth: true,
          query: destination == null || destination.isEmpty
              ? null
              : {'destination': destination},
          list: true)) as List<dynamic>;
  Future<Map<String, dynamic>> createTravelerListing(
          Map<String, dynamic> body) async =>
      (await _call('POST', '/v1/travelers/listings', auth: true, body: body))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> createDeliveryRequest(
          Map<String, dynamic> body) async =>
      (await _call('POST', '/v1/clients/requests', auth: true, body: body))
          as Map<String, dynamic>;
  Future<List<dynamic>> myListings() async =>
      (await _call('GET', '/v1/me/listings', auth: true, list: true))
          as List<dynamic>;
  Future<List<dynamic>> myRequests() async =>
      (await _call('GET', '/v1/me/requests', auth: true, list: true))
          as List<dynamic>;
  Future<List<dynamic>> myMatches() async =>
      (await _call('GET', '/v1/me/matches', auth: true, list: true))
          as List<dynamic>;
  Future<List<dynamic>> myEscrows() async =>
      (await _call('GET', '/v1/me/escrows', auth: true, list: true))
          as List<dynamic>;
  Future<void> deleteEscrow(String id) async {
    await _call('DELETE', '/v1/me/escrows/$id', auth: true);
  }
  Future<Map<String, dynamic>> createMatch(
          {required String listingID,
          required String requestID,
          required double agreedPrice,
          String? estimatedDeliveryAt}) async =>
      (await _call('POST', '/v1/matches', auth: true, body: {
        'listing_id': listingID,
        'request_id': requestID,
        'agreed_price': agreedPrice,
        if (estimatedDeliveryAt != null && estimatedDeliveryAt.isNotEmpty)
          'estimated_delivery_at': estimatedDeliveryAt
      })) as Map<String, dynamic>;
  Future<Map<String, dynamic>> createEscrow(
          {required String matchID,
          required double amount,
          String currency = 'USD'}) async =>
      (await _call('POST', '/v1/escrows', auth: true, body: {
        'match_id': matchID,
        'amount': amount,
        'currency': currency
      })) as Map<String, dynamic>;
  Future<Map<String, dynamic>> fundEscrow(String escrowID) async =>
      (await _call('POST', '/v1/escrows/$escrowID/fund', auth: true))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> releaseEscrow(String escrowID) async =>
      (await _call('POST', '/v1/escrows/$escrowID/release', auth: true))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> refundEscrow(String escrowID) async =>
      (await _call('POST', '/v1/escrows/$escrowID/refund', auth: true))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> disputeEscrow(String escrowID) async =>
      (await _call('POST', '/v1/escrows/$escrowID/dispute', auth: true))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> submitKYC(
          {required String documentType,
          required String documentReference,
          required String addressProofRef}) async {
    final out = (await _call('POST', '/v1/kyc/verifications', auth: true, body: {
      'document_type': documentType,
      'document_reference': documentReference,
      'address_proof_ref': addressProofRef
    })) as Map<String, dynamic>;
    if (currentUser != null) {
      currentUser!['kyc_status'] = 'pending';
      await persistSession();
    }
    return out;
  }
  Future<List<dynamic>> myKYC({String? status}) async =>
      (await _call('GET', '/v1/me/kyc/verifications',
          auth: true,
          query: status == null || status.isEmpty ? null : {'status': status},
          list: true)) as List<dynamic>;
  Future<Map<String, dynamic>> submitPackageVerification(
          {required String requestID,
          required String declaredContents,
          required String receiptRef,
          required String screeningMethod,
          required int riskScore}) async =>
      (await _call('POST', '/v1/packages/verifications', auth: true, body: {
        'request_id': requestID,
        'declared_contents': declaredContents,
        'receipt_ref': receiptRef,
        'screening_method': screeningMethod,
        'risk_score': riskScore
      })) as Map<String, dynamic>;
  Future<List<dynamic>> myPackageVerifications({String? status}) async =>
      (await _call('GET', '/v1/me/packages/verifications',
          auth: true,
          query: status == null || status.isEmpty ? null : {'status': status},
          list: true)) as List<dynamic>;
  Future<Map<String, dynamic>> addTrackingEvent(
          Map<String, dynamic> body) async =>
      (await _call('POST', '/v1/tracking/events', auth: true, body: body))
          as Map<String, dynamic>;
  Future<List<dynamic>> listTracking(String matchId) async =>
      (await _call('GET', '/v1/tracking/$matchId', list: true))
          as List<dynamic>;
  Future<List<dynamic>> adminUsers() async =>
      (await _call('GET', '/v1/admin/users', auth: true, list: true))
          as List<dynamic>;
  Future<List<dynamic>> adminEscrows() async =>
      (await _call('GET', '/v1/admin/escrows', auth: true, list: true))
          as List<dynamic>;
  Future<Map<String, dynamic>> adminCommissionSummary() async =>
      (await _call('GET', '/v1/admin/commissions/summary', auth: true))
          as Map<String, dynamic>;
  Future<List<dynamic>> adminKYC({String? status}) async =>
      (await _call('GET', '/v1/admin/kyc/verifications',
          auth: true,
          query: status == null || status.isEmpty ? null : {'status': status},
          list: true)) as List<dynamic>;
  Future<Map<String, dynamic>> adminReviewKYC(
          {required String id,
          required String status,
          String notes = ''}) async =>
      (await _call('POST', '/v1/admin/kyc/verifications/$id/review',
          auth: true,
          body: {'status': status, 'notes': notes})) as Map<String, dynamic>;
  Future<List<dynamic>> adminPackageVerifications({String? status}) async =>
      (await _call('GET', '/v1/admin/packages/verifications',
          auth: true,
          query: status == null || status.isEmpty ? null : {'status': status},
          list: true)) as List<dynamic>;
  Future<Map<String, dynamic>> adminReviewPackage(
          {required String id,
          required String status,
          String notes = ''}) async =>
      (await _call('POST', '/v1/admin/packages/verifications/$id/review',
          auth: true,
          body: {'status': status, 'notes': notes})) as Map<String, dynamic>;
  Future<List<dynamic>> adminOAuthProviders() async =>
      (await _call('GET', '/v1/admin/oauth/providers', auth: true, list: true))
          as List<dynamic>;
  Future<Map<String, dynamic>> adminUpsertOAuthProvider(
          {required String provider,
          required bool enabled,
          String clientID = '',
          String iosClientID = '',
          String webClientID = ''}) async =>
      (await _call('PUT', '/v1/admin/oauth/providers/$provider',
          auth: true,
          body: {
            'enabled': enabled,
            'client_id': clientID,
            'ios_client_id': iosClientID,
            'web_client_id': webClientID
          })) as Map<String, dynamic>;
  Future<List<dynamic>> myNotifications() async =>
      (await _call('GET', '/v1/me/notifications', auth: true, list: true))
          as List<dynamic>;
  Future<int> myNotificationsUnreadCount() async {
    final out = await _call('GET', '/v1/me/notifications/unread-count',
        auth: true);
    if (out is int) {
      return out;
    }
    if (out is Map<String, dynamic>) {
      return (out['unread_count'] as num?)?.toInt() ??
          (out['count'] as num?)?.toInt() ??
          0;
    }
    return 0;
  }
  Future<Map<String, dynamic>> markNotificationRead(String id) async =>
      (await _call('POST', '/v1/me/notifications/$id/read', auth: true))
          as Map<String, dynamic>;
  Future<void> deleteNotification(String id) async {
    await _call('DELETE', '/v1/me/notifications/$id', auth: true);
  }
}
