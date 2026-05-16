import 'package:supabase_flutter/supabase_flutter.dart';

Exception normalizeSupabaseAuthError(
  Object error, {
  required bool duringRegistration,
}) {
  if (error is! AuthException) {
    return Exception(error.toString());
  }

  final message = switch (error.code) {
    'over_email_send_rate_limit' =>
      'Supabase email signup is rate-limited. Rain uses app-managed alias emails, so this project must have "Enable email confirmations" turned off or a custom SMTP provider configured. Open Supabase Dashboard > Authentication > Providers > Email, disable email confirmations for this project, then try again. If you already created this account earlier, switch to Login.',
    'email_not_confirmed' =>
      'This Supabase project still requires email confirmation. Rain uses app-managed alias emails with no inbox, so you must disable "Enable email confirmations" in Supabase Dashboard > Authentication > Providers > Email before login and registration will work.',
    'email_address_invalid' =>
      'Supabase rejected the generated auth alias email. Check that Rain is pointed at the correct SUPABASE_URL for this project and rebuild the app.',
    _ => error.message,
  };

  if (!duringRegistration && message == error.message) {
    return Exception(error.message);
  }

  return Exception(message);
}
