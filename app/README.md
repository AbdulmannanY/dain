# Dain app

Flutter client for the Dain ledger. Current scope: phone OTP sign-in, profile
creation, then `link_my_ledgers()`.

```
lib/
  core/      config (Supabase URL + publishable key), phone normalization, Arabic errors
  data/      AuthRepository / ProfileRepository and their Supabase implementations
  session/   SessionController: phone -> code -> profile -> link_my_ledgers
  ui/        SessionGate and the screens
```

## Run

```
flutter pub get
flutter run -d web-server --web-port 8081 --web-hostname 0.0.0.0
```

Point a build at another project with
`--dart-define=DAIN_SUPABASE_URL=... --dart-define=DAIN_SUPABASE_KEY=...`.

## Test

```
flutter test                                          # unit + widget tests
flutter test test/live --dart-define=DAIN_LIVE=true   # real Supabase, test numbers
```

The live test signs in 966500000001 and 966500000002 (code 123456), so the
Supabase phone provider must list them as test numbers with a future
"Test OTPs valid until" date.
