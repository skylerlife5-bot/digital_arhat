import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/quick_login_service.dart';

class QuickUnlockScreen extends StatefulWidget {
  const QuickUnlockScreen({
    super.key,
    required this.user,
    required this.onUnlocked,
  });

  final User user;
  final VoidCallback onUnlocked;

  @override
  State<QuickUnlockScreen> createState() => _QuickUnlockScreenState();
}

class _QuickUnlockScreenState extends State<QuickUnlockScreen> {
  final TextEditingController _pinController = TextEditingController();
  QuickLoginConfig? _config;
  bool _loading = true;
  bool _busy = false;
  bool _biometricAvailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final config = await QuickLoginService.loadConfig(widget.user.uid);
    final biometricAvailable = await QuickLoginService.canUseRealBiometrics();

    if (!mounted) return;
    setState(() {
      _config = config;
      _biometricAvailable = biometricAvailable;
      _loading = false;
    });
  }

  Future<void> _unlockWithPin() async {
    final config = _config;
    if (config == null) return;
    if (_pinController.text.trim().length != 4) {
      setState(() => _error = '4 digit MPIN enter karein');
      return;
    }
    if (config.isLocked) {
      final until = config.lockUntil?.toLocal().toString() ?? '2 minutes';
      setState(() => _error = 'Zyada attempts ho gaye. Try again after $until');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final isValid = QuickLoginService.verifyMpin(
      uid: widget.user.uid,
      mpin: _pinController.text.trim(),
      config: config,
    );

    if (isValid) {
      await QuickLoginService.resetFailures(uid: widget.user.uid);
      QuickLoginService.markUnlocked(widget.user.uid);
      if (!mounted) return;
      widget.onUnlocked();
      return;
    }

    await QuickLoginService.registerFailure(
      uid: widget.user.uid,
      config: config,
    );
    final refreshed = await QuickLoginService.loadConfig(widget.user.uid);
    if (!mounted) return;

    setState(() {
      _config = refreshed;
      _busy = false;
      final remaining = (5 - refreshed.failedAttempts).clamp(0, 5);
      _error = remaining > 0
          ? 'Invalid MPIN. $remaining attempts left.'
          : 'Quick login temporarily locked for 2 minutes.';
    });
  }

  Future<void> _unlockWithBiometric() async {
    final config = _config;
    if (config == null || !config.biometricEnabled) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await QuickLoginService.authenticateBiometric();
    if (!mounted) return;

    if (ok) {
      await QuickLoginService.resetFailures(uid: widget.user.uid);
      QuickLoginService.markUnlocked(widget.user.uid);
      if (!mounted) return;
      widget.onUnlocked();
      return;
    }

    setState(() {
      _busy = false;
      _error = 'Biometric verify nahi hua. Password fallback use karein.';
    });
  }

  Future<void> _usePasswordFallback() async {
    await QuickLoginService.forcePasswordFallback();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEFF7F0), Color(0xFFFFF8EC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                margin: const EdgeInsets.all(20),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 74,
                                  height: 74,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Quick Unlock',
                              textAlign: TextAlign.center,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Welcome back ${widget.user.displayName?.trim().isNotEmpty == true ? widget.user.displayName : ''}',
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if ((_config?.mpinEnabled ?? false)) ...[
                              TextField(
                                controller: _pinController,
                                keyboardType: TextInputType.number,
                                obscureText: true,
                                maxLength: 4,
                                enabled: !_busy,
                                decoration: InputDecoration(
                                  labelText: '4-digit MPIN',
                                  counterText: '',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onSubmitted: (_) => _unlockWithPin(),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: _busy ? null : _unlockWithPin,
                                icon: const Icon(Icons.pin),
                                label: Text(
                                  _busy ? 'Verifying...' : 'Unlock with MPIN',
                                ),
                              ),
                            ],
                            if ((_config?.biometricEnabled ?? false) &&
                                _biometricAvailable) ...[
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _unlockWithBiometric,
                                icon: const Icon(Icons.fingerprint),
                                label: const Text('Unlock with Biometric'),
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _busy ? null : _usePasswordFallback,
                              child: const Text('Use Password Instead'),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFB71C1C),
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
