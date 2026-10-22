import 'package:url_launcher/url_launcher.dart';

/// Opens a link outside the app (WhatsApp, the browser); false when nothing
/// could open it.
typedef UrlOpener = Future<bool> Function(Uri url);

/// What the screens call to open a link. Tests replace it to see what was
/// opened without a platform.
UrlOpener openUrl = _launch;

Future<bool> _launch(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No app for it, or no plugin (a test): the caller falls back to copy.
    return false;
  }
}

/// A WhatsApp chat with [phone] (E.164 digits without '+', as ledgers store
/// it) with [text] typed in, ready to send. Spaces and line breaks are
/// percent-encoded: wa.me would show a '+' as itself.
Uri whatsappUrl(String phone, String text) =>
    Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');
