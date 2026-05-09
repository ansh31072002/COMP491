/// Maps Firebase Auth (and generic) errors to user-friendly messages.
/// Keeps the app feeling polished without exposing raw errors.
String authErrorMessage(dynamic e) {
  final s = e?.toString() ?? '';
  if (s.contains('wrong-password') || s.contains('invalid-credential')) {
    return 'Wrong email or password. Please try again.';
  }
  if (s.contains('user-not-found')) {
    return 'No account found with this email. Try signing up.';
  }
  if (s.contains('invalid-email')) {
    return 'Please enter a valid email address.';
  }
  if (s.contains('email-already-in-use')) {
    return 'This email is already registered. Try logging in.';
  }
  if (s.contains('weak-password')) {
    return 'Password is too weak. Use at least 6 characters.';
  }
  if (s.contains('too-many-requests')) {
    return 'Too many attempts. Please wait a minute and try again.';
  }
  if (s.contains('invalid-sender') || s.contains('invalid-sender-email')) {
    return 'Password reset email is not configured. Contact support.';
  }
  if (s.contains('network')) {
    return 'Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}
