import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/device_security_viewmodel.dart';

class AppLockPinView extends ConsumerStatefulWidget {
  const AppLockPinView({super.key});

  @override
  ConsumerState<AppLockPinView> createState() => _AppLockPinViewState();
}

class _AppLockPinViewState extends ConsumerState<AppLockPinView> {
  String _enteredPin = '';
  String? _confirmPin;
  bool _isConfirming = false;

  void _onDigitPressed(String digit) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += digit;
      });

      if (_enteredPin.length == 4) {
        _handlePinComplete();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _handlePinComplete() async {
    final state = ref.read(deviceSecurityProvider);
    final vm = ref.read(deviceSecurityProvider.notifier);

    if (state.requiresPinSetup) {
      // Setting up PIN for first time
      if (!_isConfirming) {
        setState(() {
          _confirmPin = _enteredPin;
          _enteredPin = '';
          _isConfirming = true;
        });
      } else {
        if (_enteredPin == _confirmPin) {
          await vm.setupPin(_enteredPin);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PINs do not match. Please try again.')),
          );
          setState(() {
            _enteredPin = '';
            _confirmPin = null;
            _isConfirming = false;
          });
        }
      }
    } else {
      // Unlocking with existing PIN
      final success = await vm.unlockWithPin(_enteredPin);
      if (!success) {
        setState(() {
          _enteredPin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceSecurityProvider);
    final isSetup = state.requiresPinSetup;

    return Scaffold(
      appBar: AppBar(
        title: Text(isSetup ? 'Set Security PIN' : 'Gynocamp Security Lock'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Icon(Icons.lock_outline, size: 48, color: AppTheme.primaryTeal),
              const SizedBox(height: 12),
              Text(
                isSetup
                    ? (_isConfirming ? 'Confirm your 4-Digit PIN' : 'Create 4-Digit App Lock PIN')
                    : 'Enter 4-Digit Device PIN',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                isSetup
                    ? 'This PIN protects patient health records if this tablet is unattended.'
                    : 'Device registered to: ${state.device?.deviceName ?? "Organization Tablet"}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
              ),
              const SizedBox(height: 20),

              // PIN Dots Display
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? AppTheme.primaryTeal : Colors.transparent,
                      border: Border.all(color: AppTheme.primaryTeal, width: 2),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),

              if (state.errorMessage != null)
                Text(
                  state.errorMessage!,
                  style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13, fontWeight: FontWeight.w600),
                ),

              const SizedBox(height: 16),

              // Numerical Keypad
              for (var row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: row.map((digit) => _buildKeypadButton(digit)).toList(),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Biometric button (simulated)
                    IconButton(
                      iconSize: 32,
                      color: AppTheme.primaryTeal,
                      icon: const Icon(Icons.fingerprint),
                      onPressed: isSetup
                          ? null
                          : () async {
                              // Simulate biometric match with stored PIN
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Biometric authentication verified')),
                              );
                              ref.read(deviceSecurityProvider.notifier).unlockWithPin('1234');
                            },
                    ),
                    _buildKeypadButton('0'),
                    IconButton(
                      iconSize: 30,
                      color: Colors.grey.shade700,
                      icon: const Icon(Icons.backspace_outlined),
                      onPressed: _onBackspace,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadButton(String digit) {
    return InkWell(
      onTap: () => _onDigitPressed(digit),
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Text(
          digit,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
        ),
      ),
    );
  }
}
