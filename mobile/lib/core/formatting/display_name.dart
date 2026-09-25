/// The name to show for a User: their [displayName], or, while they haven't
/// set one, the last 4 digits of their [phoneNumber] (e.g. `•••• 4821`), so
/// nobody is ever shown as blank (ADR 0003).
///
/// Every surface that shows a User's name goes through this, rather than
/// handling a missing display name itself.
String displayName({
  required String? displayName,
  required String phoneNumber,
}) {
  final name = displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
  final lastFour = digits.substring(digits.length < 4 ? 0 : digits.length - 4);
  return '•••• $lastFour';
}
