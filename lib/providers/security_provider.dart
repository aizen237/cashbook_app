import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityState {
  final bool isPinEnabled;
  final bool isBiometricEnabled;
  final bool isAuthenticated;
  final bool isBiometricSupported;

  const SecurityState({
    this.isPinEnabled = false,
    this.isBiometricEnabled = false,
    this.isAuthenticated = false,
    this.isBiometricSupported = false,
  });

  SecurityState copyWith({
    bool? isPinEnabled,
    bool? isBiometricEnabled,
    bool? isAuthenticated,
    bool? isBiometricSupported,
  }) {
    return SecurityState(
      isPinEnabled: isPinEnabled ?? this.isPinEnabled,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isBiometricSupported: isBiometricSupported ?? this.isBiometricSupported,
    );
  }
}

class SecurityNotifier extends Notifier<SecurityState> {
  static const String _keyPin = 'security_pin_code';
  static const String _keyPinEnabled = 'security_pin_enabled';
  static const String _keyBiometricEnabled = 'security_biometric_enabled';

  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  SecurityState build() {
    _init();
    return const SecurityState();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final pinEnabled = prefs.getBool(_keyPinEnabled) ?? false;
    final biometricEnabled = prefs.getBool(_keyBiometricEnabled) ?? false;

    bool canCheckBiometrics = false;
    try {
      canCheckBiometrics = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {}

    state = SecurityState(
      isPinEnabled: pinEnabled,
      isBiometricEnabled: biometricEnabled,
      isAuthenticated: !pinEnabled,
      isBiometricSupported: canCheckBiometrics,
    );
  }

  Future<bool> verifyPin(String inputPin) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(_keyPin);

    if (savedPin == inputPin) {
      state = state.copyWith(isAuthenticated: true);
      return true;
    }
    return false;
  }

  Future<void> setPin(String newPin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPin, newPin);
    await prefs.setBool(_keyPinEnabled, true);

    state = state.copyWith(
      isPinEnabled: true,
      isAuthenticated: true,
    );
  }

  Future<void> disablePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPin);
    await prefs.setBool(_keyPinEnabled, false);
    await prefs.setBool(_keyBiometricEnabled, false);

    state = state.copyWith(
      isPinEnabled: false,
      isBiometricEnabled: false,
      isAuthenticated: true,
    );
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricEnabled, enabled);
    state = state.copyWith(isBiometricEnabled: enabled);
  }

  Future<bool> authenticateWithBiometrics() async {
    if (!state.isBiometricEnabled || !state.isBiometricSupported) return false;

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access Cashbook App',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated) {
        state = state.copyWith(isAuthenticated: true);
        return true;
      }
    } catch (_) {}
    return false;
  }

  void lockApp() {
    if (state.isPinEnabled) {
      state = state.copyWith(isAuthenticated: false);
    }
  }
}

final securityProvider =
    NotifierProvider<SecurityNotifier, SecurityState>(SecurityNotifier.new);
