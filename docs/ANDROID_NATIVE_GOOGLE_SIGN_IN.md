# Android native Google sign-in release gate

Android uses Credential Manager's system account chooser. It does not open a
Custom Tab, WebView, or external browser. Google must be able to match the APK
to an Android OAuth client before this flow can succeed.

## One-time production setup

1. Create one stable Android signing keystore and keep it outside the
   repository. Never commit the keystore or its password.
2. Add these protected GitHub Actions secrets:
   - `ANDROID_KEYSTORE_BASE64`: base64-encoded keystore bytes
   - `ANDROID_KEYSTORE_ALIAS`: key alias
   - `ANDROID_KEYSTORE_PASSWORD`: key/store password
3. Print that key's SHA-1 certificate fingerprint with `keytool -list -v`.
4. In the same Google Auth Platform project as the configured Web client ID,
   create an **Android** OAuth client with:
   - package: `com.mehmetdemirel.colonydominion`
   - SHA-1: the stable signing certificate fingerprint
5. Keep the Web OAuth client ID first in Supabase's Google provider client ID
   list. The app requests an ID token for that Web client and exchanges it with
   Supabase using the raw nonce.

If Google Play App Signing and direct APK downloads are both used, register an
Android OAuth client for each distribution certificate. The canonical
`Build Android APK` workflow intentionally refuses to publish a one-use signing
certificate because the next APK would no longer match Google OAuth.

## Verification

- The login button must show Android's native Google account chooser without
  hiding or leaving the game.
- The APK must contain `ColonyGoogleIdentity` and Credential Manager classes.
- `apksigner verify --print-certs` must report the same SHA-1 registered in the
  Google Auth Platform.
