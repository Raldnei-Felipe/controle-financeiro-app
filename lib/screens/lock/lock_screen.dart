import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../services/security_service.dart';

class LockGate extends StatefulWidget {
  final Widget child;

  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  final SecurityService securityService = SecurityService();

  bool isLoading = true;
  bool hasPin = false;
  bool biometricEnabled = false;
  bool isUnlocked = false;

  bool _wentToBackground = false;

  String enteredPin = '';
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (isUnlocked) {
        _wentToBackground = true;
      }

      return;
    }

    if (state == AppLifecycleState.resumed && _wentToBackground) {
      _wentToBackground = false;

      if (hasPin) {
        setState(() {
          isUnlocked = false;
          enteredPin = '';
          errorMessage = null;
        });
      }
    }
  }

  Future<void> _initialize() async {
    final pinExists = await securityService.hasPin();

    if (!mounted) {
      return;
    }

    if (!pinExists) {
      setState(() {
        hasPin = false;
        isLoading = false;
      });

      return;
    }

    final biometric = await securityService.isBiometricEnabled();

    if (!mounted) {
      return;
    }

    setState(() {
      hasPin = true;
      biometricEnabled = biometric;
      isLoading = false;
    });

    if (biometricEnabled) {
      await _tryBiometrics();
    }
  }

  Future<void> _tryBiometrics() async {
    final success = await securityService.authenticateWithBiometrics();

    if (!mounted || !success) {
      return;
    }

    setState(() {
      isUnlocked = true;
    });
  }

  Future<void> _submitPin() async {
    if (enteredPin.length != 4) {
      return;
    }

    final valid = await securityService.validatePin(enteredPin);

    if (!mounted) {
      return;
    }

    if (valid) {
      setState(() {
        isUnlocked = true;
        enteredPin = '';
        errorMessage = null;
      });

      return;
    }

    HapticFeedback.vibrate();

    setState(() {
      enteredPin = '';
      errorMessage = 'PIN incorreto. Tente novamente.';
    });
  }

  void _addDigit(String digit) {
    if (enteredPin.length >= 4) {
      return;
    }

    setState(() {
      enteredPin += digit;
      errorMessage = null;
    });

    if (enteredPin.length == 4) {
      _submitPin();
    }
  }

  void _removeDigit() {
    if (enteredPin.isEmpty) {
      return;
    }

    setState(() {
      enteredPin = enteredPin.substring(0, enteredPin.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (!hasPin || isUnlocked) {
      return widget.child;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _buildLockScreen(),
    );
  }

  Widget _buildLockScreen() {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.lock_outline, size: 52, color: AppColors.orange),
              const SizedBox(height: 14),
              const Text(
                'App bloqueado',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Digite seu PIN de 4 dígitos',
                style: TextStyle(color: AppColors.gray),
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final filled = index < enteredPin.length;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? AppColors.orange : Colors.transparent,
                      border: Border.all(color: AppColors.orange, width: 2),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 10),
              if (errorMessage != null)
                Text(
                  errorMessage!,
                  style: const TextStyle(color: AppColors.red),
                ),
              const SizedBox(height: 18),
              _buildKeypad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      children: [
        ...rows.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map(_buildDigitKey).toList(),
          );
        }),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildBiometricKey(),
            _buildDigitKey('0'),
            _buildBackspaceKey(),
          ],
        ),
      ],
    );
  }

  Widget _buildDigitKey(String digit) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 74,
        height: 74,
        child: FilledButton.tonal(
          onPressed: () => _addDigit(digit),
          style: FilledButton.styleFrom(shape: const CircleBorder()),
          child: Text(digit, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  Widget _buildBiometricKey() {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 74,
        height: 74,
        child: biometricEnabled
            ? IconButton(
                onPressed: _tryBiometrics,
                tooltip: 'Desbloquear com biometria',
                icon: const Icon(Icons.fingerprint, size: 34),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 74,
        height: 74,
        child: IconButton(
          onPressed: _removeDigit,
          tooltip: 'Apagar',
          icon: const Icon(Icons.backspace_outlined, size: 26),
        ),
      ),
    );
  }
}
