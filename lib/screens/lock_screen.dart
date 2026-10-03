import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/security_provider.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _enteredPin = '';
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometricAuth();
    });
  }

  Future<void> _tryBiometricAuth() async {
    final security = ref.read(securityProvider);
    if (security.isBiometricEnabled && security.isBiometricSupported) {
      await ref.read(securityProvider.notifier).authenticateWithBiometrics();
    }
  }

  void _onKeyPress(String digit) async {
    if (_enteredPin.length < 4) {
      setState(() {
        _isError = false;
        _enteredPin += digit;
      });

      if (_enteredPin.length == 4) {
        final success =
            await ref.read(securityProvider.notifier).verifyPin(_enteredPin);
        if (!success) {
          setState(() {
            _isError = true;
            _enteredPin = '';
          });
        }
      }
    }
  }

  void _onDelete() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _isError = false;
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securityProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Icon(Icons.lock_outline, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 16),
              const Text(
                'Enter PIN',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isError
                    ? 'Incorrect PIN, try again'
                    : 'Enter 4-digit security PIN',
                style: TextStyle(
                  color: _isError ? Colors.red : Colors.grey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              // PIN Indicator Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? (_isError ? Colors.red : Colors.blueAccent)
                          : Colors.grey.shade300,
                    ),
                  );
                }),
              ),
              const Spacer(),

              // Numeric Keypad
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 1.4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  for (var i = 1; i <= 9; i++) _buildKeyPadButton(i.toString()),
                  if (security.isBiometricEnabled &&
                      security.isBiometricSupported)
                    IconButton(
                      icon: const Icon(Icons.fingerprint,
                          size: 32, color: Colors.blueAccent),
                      onPressed: () => ref
                          .read(securityProvider.notifier)
                          .authenticateWithBiometrics(),
                    )
                  else
                    const SizedBox.shrink(),
                  _buildKeyPadButton('0'),
                  IconButton(
                    icon: const Icon(Icons.backspace_outlined, size: 24),
                    onPressed: _onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyPadButton(String label) {
    return InkWell(
      onTap: () => _onKeyPress(label),
      borderRadius: BorderRadius.circular(40),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
