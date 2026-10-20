import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// One Arabic sentence for anything the sign-in flow can throw.
String arabicMessageFor(Object error) {
  // dart:io is unavailable on web, so network failures are recognised by
  // their type names (SocketException, http's ClientException). This check
  // comes first: AuthRetryableFetchException is itself an AuthException.
  final text = error.toString();
  if (error is TimeoutException ||
      error is AuthRetryableFetchException ||
      text.contains('SocketException') ||
      text.contains('ClientException')) {
    return 'لا يوجد اتصال بالإنترنت.';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'otp_expired':
        return 'الرمز غير صحيح أو انتهت صلاحيته.';
      case 'over_sms_send_rate_limit':
      case 'over_request_rate_limit':
        return 'طلبات كثيرة. انتظر قليلاً ثم حاول مجدداً.';
      case 'sms_send_failed':
        return 'تعذّر إرسال الرمز إلى هذا الرقم.';
      case 'phone_provider_disabled':
      case 'signup_disabled':
        return 'الدخول بالجوال غير متاح حالياً.';
      case 'not_signed_in':
      case 'no_session':
      case 'session_expired':
        return 'انتهت الجلسة. سجّل الدخول من جديد.';
    }
    return 'تعذّر تسجيل الدخول. حاول مجدداً.';
  }
  if (error is PostgrestException) {
    return 'تعذّر إتمام العملية. حاول مجدداً.';
  }
  return 'حدث خطأ غير متوقع. حاول مجدداً.';
}
