/// Build-time configuration. The publishable key is designed to ship inside
/// the app (RLS guards the data), so the real project is the default and a
/// `--dart-define` can point a build at another project.
abstract final class DainConfig {
  static const supabaseUrl = String.fromEnvironment(
    'DAIN_SUPABASE_URL',
    defaultValue: 'https://mxnjwaofjlxxdjizjsfb.supabase.co',
  );

  static const supabaseKey = String.fromEnvironment(
    'DAIN_SUPABASE_KEY',
    defaultValue: 'sb_publishable_JTVwmwscU9kAwi3PM2EQMQ_shfAYx5X',
  );

  /// The web confirmation page (share/ in the repository, on GitHub Pages).
  /// The token goes after '#', so it never reaches a server log.
  static const shareBaseUrl = String.fromEnvironment(
    'DAIN_SHARE_URL',
    defaultValue: 'https://abdulmannany.github.io/dain/',
  );

  static String shareUrl(String token) => '$shareBaseUrl#$token';
}
