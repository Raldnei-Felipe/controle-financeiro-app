import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SecurityService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final LocalAuthentication _auth = LocalAuthentication();

  static const String _pinKey = 'app_pin';
  static const String _biometricKey = 'use_biometric';

  Future<bool> hasPin() async {
    final pin = await _storage.read(key: _pinKey);

    return pin != null && pin.length == 4;
  }

  Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  Future<bool> validatePin(String pin) async {
    final saved = await _storage.read(key: _pinKey);

    return saved != null && saved == pin;
  }

  Future<void> removePin() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _biometricKey);
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricKey);

    return value == '1';
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _storage.write(key: _biometricKey, value: value ? '1' : '0');
  }

  Future<bool> canUseBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();

      return canCheck && supported;
    } catch (error) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Desbloqueie o app financeiro',
      );
    } catch (error) {
      return false;
    }
  }
}
