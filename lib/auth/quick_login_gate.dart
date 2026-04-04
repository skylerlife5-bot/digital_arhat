import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routes.dart';
import '../services/auth_service.dart';
import 'quick_login_service.dart';

class QuickLoginGate extends StatefulWidget {
  const QuickLoginGate({super.key, required this.userId, required this.child});

  final String userId;
  final Widget child;

  @override
  State<QuickLoginGate> createState() => _QuickLoginGateState();
}

class _QuickLoginGateState extends State<QuickLoginGate> {
  bool _loading = true;
  bool _requiresUnlock = false;
  bool _offerSetup = false;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  @override
  void didUpdateWidget(covariant QuickLoginGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _evaluate();
    }
  }

  Future<void> _evaluate() async {
    setState(() {
      _loading = true;
      _requiresUnlock = false;
      _offerSetup = false;
    });

    final bool requiresUnlock = await QuickLoginService.needsQuickUnlock(
      widget.userId,
    );
    final bool offerSetup =
        !requiresUnlock &&
        await QuickLoginService.shouldOfferSetup(widget.userId);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _requiresUnlock = requiresUnlock;
      _offerSetup = offerSetup;
    });
  }

  Future<void> _onSetupCompleted() async {
    QuickLoginService.markSessionUnlocked(widget.userId);
    if (!mounted) return;
    setState(() => _offerSetup = false);
  }

  Future<void> _onSetupSkipped() async {
    await QuickLoginService.markSetupPrompted(widget.userId);
    if (!mounted) return;
    setState(() => _offerSetup = false);
  }

  void _onUnlocked() {
    if (!mounted) return;
    setState(() => _requiresUnlock = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_requiresUnlock) {
      return QuickUnlockScreen(userId: widget.userId, onUnlocked: _onUnlocked);
    }

    if (_offerSetup) {
      return QuickLoginSetupScreen(
        userId: widget.userId,
        onCompleted: _onSetupCompleted,
        onSkip: _onSetupSkipped,
      );
    }

    return widget.child;
  }
}

class QuickUnlockScreen extends StatefulWidget {
  const QuickUnlockScreen({
    super.key,
    required this.userId,
    required this.onUnlocked,
  });

  final String userId;
  final VoidCallback onUnlocked;

  @override
  State<QuickUnlockScreen> createState() => _QuickUnlockScreenState();
}

class _QuickUnlockScreenState extends State<QuickUnlockScreen> {
  static const Color _greenDark = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  final TextEditingController _pinController = TextEditingController();
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometricOnOpen());
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometricOnOpen() async {
    final bool enabled = await QuickLoginService.isBiometricEnabled(
      widget.userId,
    );
    if (!enabled) return;
    final bool canUse = await QuickLoginService.canUseBiometric();
    if (!canUse) return;
    await _unlockWithBiometric();
  }

  Future<void> _unlockWithBiometric() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final bool ok = await QuickLoginService.authenticateBiometric();
    if (ok) {
      QuickLoginService.markSessionUnlocked(widget.userId);
      if (mounted) widget.onUnlocked();
    } else {
      _showSnack('Biometric verification failed');
    }
    if (mounted) setState(() => _isBusy = false);
  }

  Future<void> _unlockWithPin() async {
    if (_isBusy) return;
    final String pin = _pinController.text.trim();
    if (pin.length != 4) {
      _showSnack('Enter 4-digit MPIN');
      return;
    }

    setState(() => _isBusy = true);
    final bool ok = await QuickLoginService.verifyMpin(
      userId: widget.userId,
      pin: pin,
    );
    if (ok) {
      QuickLoginService.markSessionUnlocked(widget.userId);
      if (mounted) widget.onUnlocked();
    } else {
      _showSnack('Incorrect MPIN');
    }
    if (mounted) setState(() => _isBusy = false);
  }

  Future<void> _logoutAndUsePassword() async {
    await FirebaseAuth.instance.signOut();
    await AuthService().clearPersistedSessionUid();
    QuickLoginService.clearSessionUnlock(widget.userId);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(Routes.authWrapper, (route) => false);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _greenDark,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                color: const Color(0xFF0E3824),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.lock_rounded, color: _gold, size: 36),
                      const SizedBox(height: 8),
                      const Text(
                        'Quick Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Continue with MPIN or biometric',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          counterText: '',
                          labelText: '4-digit MPIN',
                          labelStyle: TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Color(0x22000000),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _isBusy ? null : _unlockWithPin,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: _gold,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Unlock with MPIN'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isBusy ? null : _unlockWithBiometric,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: _gold),
                        ),
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Use Biometric'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isBusy ? null : _logoutAndUsePassword,
                        child: const Text(
                          'Use password login instead',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
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

class QuickLoginSetupScreen extends StatefulWidget {
  const QuickLoginSetupScreen({
    super.key,
    required this.userId,
    required this.onCompleted,
    required this.onSkip,
  });

  final String userId;
  final Future<void> Function() onCompleted;
  final Future<void> Function() onSkip;

  @override
  State<QuickLoginSetupScreen> createState() => _QuickLoginSetupScreenState();
}

class _QuickLoginSetupScreenState extends State<QuickLoginSetupScreen> {
  static const Color _greenDark = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _biometricEnabled = true;
  bool _saving = false;
  bool _canUseBiometric = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricSupport();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _loadBiometricSupport() async {
    final bool canUse = await QuickLoginService.canUseBiometric();
    if (!mounted) return;
    setState(() {
      _canUseBiometric = canUse;
      if (!canUse) {
        _biometricEnabled = false;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final String pin = _pinController.text.trim();
    final String confirm = _confirmController.text.trim();

    if (pin.length != 4) {
      _showSnack('MPIN must be 4 digits');
      return;
    }
    if (pin != confirm) {
      _showSnack('MPIN does not match');
      return;
    }

    setState(() => _saving = true);
    await QuickLoginService.configureMpin(userId: widget.userId, pin: pin);
    await QuickLoginService.setBiometricEnabled(
      userId: widget.userId,
      enabled: _canUseBiometric && _biometricEnabled,
    );
    await QuickLoginService.markSetupPrompted(widget.userId);
    await widget.onCompleted();
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.onSkip();
    if (mounted) setState(() => _saving = false);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _greenDark,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                color: const Color(0xFF0E3824),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'Enable Quick Login',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Set your 4-digit MPIN. You can also use device biometric unlock.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _pinController,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          counterText: '',
                          labelText: 'Create MPIN',
                          labelStyle: TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Color(0x22000000),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _confirmController,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          counterText: '',
                          labelText: 'Confirm MPIN',
                          labelStyle: TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Color(0x22000000),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        value: _biometricEnabled,
                        onChanged: _canUseBiometric
                            ? (value) =>
                                  setState(() => _biometricEnabled = value)
                            : null,
                        title: const Text(
                          'Enable biometric unlock',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          _canUseBiometric
                              ? 'Face/Fingerprint as quick unlock option'
                              : 'Biometric not available on this device',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        activeThumbColor: _gold,
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: _gold,
                          foregroundColor: Colors.black,
                        ),
                        child: Text(_saving ? 'Saving...' : 'Save Quick Login'),
                      ),
                      TextButton(
                        onPressed: _saving ? null : _skip,
                        child: const Text(
                          'Skip for now',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
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
