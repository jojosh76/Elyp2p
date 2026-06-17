import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../api/api_client.dart';
import '../home/home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, this.onAuthenticated});
  final ApiClient api;
  final VoidCallback? onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phoneLocal = TextEditingController();
  final _address = TextEditingController();
  final _passport = TextEditingController();
  final _country = TextEditingController();
  final _otp = TextEditingController();
  String _role = 'client';
  String _selectedDialCode = '1';
  String _selectedCountryCode = 'US';
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  final Map<String, Map<String, dynamic>> _providerConfigs = {};
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      setState(() => _error = null);
    });
    _loadProviderConfigs();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phoneLocal.dispose();
    _address.dispose();
    _passport.dispose();
    _country.dispose();
    _otp.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProviderConfigs() async {
    try {
      final rows = await widget.api.authProviders();
      final next = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final map = (row as Map).cast<String, dynamic>();
        final provider = (map['provider'] as String? ?? '').trim().toLowerCase();
        if (provider.isNotEmpty) {
          next[provider] = map;
        }
      }
      if (mounted) {
        setState(() => _providerConfigs
          ..clear()
          ..addAll(next));
      }
    } catch (_) {}
  }

  Future<void> _submit({required bool register}) async {
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    final phone = _composePhoneE164();
    final address = _address.text.trim();
    final passport = _passport.text.trim();
    final country = _country.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }
    if (register && name.isEmpty) {
      setState(() => _error = 'Full name is required for registration');
      return;
    }
    if (register) {
      final pwdError = _passwordPolicyError(password);
      if (pwdError != null) {
        setState(() => _error = pwdError);
        return;
      }
      if (_role == 'client' && phone.isEmpty) {
        setState(() => _error = 'Phone is required for client registration');
        return;
      }
      if (_role == 'traveler' &&
          (phone.isEmpty || address.isEmpty || passport.isEmpty || country.isEmpty)) {
        setState(() => _error = 'Traveler requires phone, address, passport and country');
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = register
          ? await widget.api.register(
              email: email,
              password: password,
              fullName: name,
              role: _role,
              phone: phone,
              permanentAddress: address,
              passportNumber: passport,
              countryOfResidence: country,
            )
          : await widget.api.login(email, password);
      if ((data['otp_required'] as bool?) == true) {
        final session = (data['otp_session_id'] as String? ?? '').trim();
        final devCode = (data['dev_otp_code'] as String? ?? '').trim();
        if (session.isEmpty) {
          throw Exception('Missing OTP session');
        }
        await _showOTPDialog(session, devCode: devCode);
        return;
      }
      await _finalizeAuthSuccess(data);
    } catch (e) {
      var msg = e.toString().replaceFirst('Exception: ', '');
      if (register && msg.toLowerCase().contains('email already exists')) {
        msg = 'This email already has an account. Use Login instead.';
      }
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showOTPDialog(String sessionID, {String devCode = ''}) async {
    _otp.clear();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Phone OTP Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the 6-digit code sent to your phone.'),
            if (devCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Dev OTP: $devCode', style: const TextStyle(fontWeight: FontWeight.w700)),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                'No dev OTP returned by server. Use a client account and ensure OTP_DEV_MODE is enabled.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'OTP Code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = _otp.text.trim();
              if (code.length < 4) {
                setState(() => _error = 'Invalid OTP code');
                return;
              }
              try {
                final data = await widget.api.verifyOtp(otpSessionID: sessionID, otpCode: code);
                if (!mounted) return;
                Navigator.of(this.context).pop();
                await _finalizeAuthSuccess(data);
              } catch (e) {
                if (!mounted) return;
                setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizeAuthSuccess(Map<String, dynamic> data) async {
    widget.api.token = data['token'] as String;
    await widget.api.persistSession();
    if (!mounted) return;
    if (widget.onAuthenticated != null) {
      widget.onAuthenticated!();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api)),
    );
  }

  Future<void> _socialSignIn(String provider) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (provider) {
        case 'google':
          final googleCfg = _providerConfigs['google'];
          final google = _buildGoogleSignIn(googleCfg);
          final account = await google.signIn();
          if (account == null) {
            throw Exception('Google sign-in cancelled');
          }
          final auth = await account.authentication;
          final accessToken = auth.accessToken;
          if (accessToken == null || accessToken.isEmpty) {
            throw Exception('Google access token is missing');
          }
          await widget.api.socialLogin(provider: 'google', accessToken: accessToken);
          break;
        case 'apple':
          final cred = await SignInWithApple.getAppleIDCredential(
            scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
          );
          final idToken = cred.identityToken ?? '';
          if (idToken.isEmpty) {
            throw Exception('Apple ID token is missing');
          }
          final fullName = [
            cred.givenName ?? '',
            cred.familyName ?? '',
          ].where((e) => e.trim().isNotEmpty).join(' ');
          await widget.api.socialLogin(
            provider: 'apple',
            idToken: idToken,
            email: cred.email ?? _email.text.trim(),
            fullName: fullName,
          );
          break;
      }
      await widget.api.persistSession();
      if (!mounted) return;
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!();
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api)),
      );
    } on PlatformException catch (e) {
      final msg = '${e.code}: ${e.message ?? ''}'.toLowerCase();
      if (msg.contains('sign_in_failed') && msg.contains('10')) {
        setState(() {
          _error = 'Google Sign-In config error (code 10). Ask admin to set OAuth Client IDs and configure Android SHA fingerprints for package com.example.p2p_delivery_mobile.';
        });
      } else {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGoogleEnabled = (_providerConfigs['google']?['enabled'] as bool?) ?? true;
    final isAppleEnabled = (_providerConfigs['apple']?['enabled'] as bool?) ?? true;
    final isRegister = _tabController.index == 1;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E2D24), Color(0xFF133D53), Color(0xFF0A6A5F)],
          ),
        ),
        child: SafeArea(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 700),
            tween: Tween(begin: 0.95, end: 1),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(scale: value, child: child),
            ),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 14),
                const Text(
                  'Elysian Flee',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Trusted traveler-powered delivery',
                  style: TextStyle(color: Color(0xFFCCF0EA)),
                ),
                const SizedBox(height: 4),
                Text(
                  isRegister
                      ? 'Create a new account to start shipping with travelers.'
                      : 'Log in to continue to your account.',
                  style: const TextStyle(color: Color(0xFFE2F5F1)),
                ),
                const SizedBox(height: 20),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        children: [
                          TabBar(
                            controller: _tabController,
                            indicator: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            labelColor: Colors.white,
                            unselectedLabelColor: const Color(0xFFC5DAD6),
                            tabs: const [Tab(text: 'Login'), Tab(text: 'Register')],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              filled: true,
                              fillColor: Colors.white,
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (isRegister) ...[
                            TextField(
                              controller: _name,
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _phoneLocal,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                hintText: 'e.g. 782123456',
                                prefixIcon: InkWell(
                                  onTap: () {
                                    showCountryPicker(
                                      context: context,
                                      showPhoneCode: true,
                                      favorite: const ['US', 'GB', 'RW', 'KE', 'NG', 'IN', 'FR'],
                                        onSelect: (country) {
                                        setState(() {
                                          _selectedDialCode = country.phoneCode;
                                          _selectedCountryCode = country.countryCode;
                                        });
                                      },
                                    );
                                  },
                                  child: Container(
                                    alignment: Alignment.center,
                                    width: 108,
                                    child: Text(
                                      '$_selectedCountryCode +$_selectedDialCode',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_role == 'traveler') ...[
                              TextField(
                                controller: _country,
                                decoration: const InputDecoration(
                                  labelText: 'Country of Residence',
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _address,
                                decoration: const InputDecoration(
                                  labelText: 'Permanent Address',
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _passport,
                                decoration: const InputDecoration(
                                  labelText: 'Passport Number',
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            DropdownButtonFormField<String>(
                              initialValue: _role,
                              decoration: const InputDecoration(
                                labelText: 'Role',
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'client', child: Text('Client')),
                                DropdownMenuItem(value: 'traveler', child: Text('Traveler')),
                                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                              ],
                              onChanged: (v) => setState(() => _role = v ?? 'client'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_error != null)
                            Text(_error!, style: const TextStyle(color: Color(0xFFFFD2D2))),
                          const SizedBox(height: 6),
                          FilledButton(
                            onPressed: _loading
                                ? null
                                : () => _submit(register: isRegister),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: const Color(0xFFE3F76A),
                              foregroundColor: const Color(0xFF112B1F),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(isRegister ? 'Create Account' : 'Login'),
                          ),
                          const SizedBox(height: 10),
                          const Divider(color: Colors.white38),
                          const SizedBox(height: 6),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final singleColumn = constraints.maxWidth < 360;
                              final googleButton = _socialButton(
                                label: 'Google',
                                enabled: isGoogleEnabled && !_loading,
                                onTap: () => _socialSignIn('google'),
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                icon: const _GoogleGlyph(),
                              );
                              final appleButton = _socialButton(
                                label: 'Apple',
                                enabled: isAppleEnabled && !_loading,
                                onTap: () => _socialSignIn('apple'),
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                icon: const Icon(Icons.apple),
                              );
                              if (singleColumn) {
                                return Column(
                                  children: [
                                    SizedBox(width: double.infinity, child: googleButton),
                                    const SizedBox(height: 8),
                                    SizedBox(width: double.infinity, child: appleButton),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: googleButton),
                                  const SizedBox(width: 8),
                                  Expanded(child: appleButton),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _passwordPolicyError(String password) {
    if (password.length < 10) return 'Password must be at least 10 characters';
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSymbol = password.contains(RegExp(r'[^A-Za-z0-9]'));
    if (!hasUpper || !hasLower || !hasDigit || !hasSymbol) {
      return 'Password must include uppercase, lowercase, number and symbol';
    }
    return null;
  }

  String _composePhoneE164() {
    final raw = _phoneLocal.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (raw.isEmpty) return '';
    if (raw.startsWith('+')) return raw;
    final local = raw.replaceFirst(RegExp(r'^0+'), '');
    return '+$_selectedDialCode$local';
  }

  GoogleSignIn _buildGoogleSignIn(Map<String, dynamic>? cfg) {
    final iosClient = (cfg?['ios_client_id'] as String? ?? '').trim();
    final webClient = (cfg?['web_client_id'] as String? ?? '').trim();

    if (kIsWeb) {
      return GoogleSignIn(
        scopes: const ['openid', 'email', 'profile'],
        clientId: webClient.isEmpty ? null : webClient,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return GoogleSignIn(
        scopes: const ['openid', 'email', 'profile'],
        clientId: iosClient.isEmpty ? null : iosClient,
      );
    }
    // Android uses package name + SHA fingerprints configured in Google Cloud.
    // serverClientId should be the Web OAuth client ID when available.
    return GoogleSignIn(
      scopes: const ['openid', 'email', 'profile'],
      serverClientId: webClient.isEmpty ? null : webClient,
    );
  }

  Widget _socialButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color foregroundColor,
    required Widget icon,
  }) {
    return FilledButton(
      onPressed: enabled ? onTap : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A73E8),
          height: 1,
        ),
      ),
    );
  }
}
