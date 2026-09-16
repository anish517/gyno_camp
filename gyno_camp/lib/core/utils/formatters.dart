import 'package:flutter/services.dart';

/// A [TextInputFormatter] that automatically converts all incoming characters
/// to uppercase (BLOCK LETTERS). Works reliably across all platforms (Web,
/// Desktop, iOS, Android) and with all input sources (virtual keyboard, physical
/// hardware keyboard, copy-paste).
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: newValue.composing,
    );
  }
}
