# APK signing and updates

Debug APKs are for a trial. Before production, create a permanent company signing
key. A debug-signed installation cannot be updated in place by a different certificate.

Use the JDK's `keytool` and enter passwords at its prompts:

```powershell
keytool -genkeypair -v -keystore android/gm-delivery-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias gm-delivery
```

Create `android/key.properties`:

```properties
storeFile=../gm-delivery-release.jks
storePassword=YOUR_PRIVATE_STORE_PASSWORD
keyAlias=gm-delivery
keyPassword=YOUR_PRIVATE_KEY_PASSWORD
```

The path is relative to `android/app`. Git ignores these private files. Keep an
encrypted backup of the key and passwords; do not share them in chat.

```powershell
flutter build apk --release --dart-define-from-file=config/cloud.json
```

Output: `build/app/outputs/flutter-apk/app-release.apk`. Increment the build number
after `+` in `pubspec.yaml` for updates. Preserve app ID and signing certificate,
and test an update on a phone containing saved records before distributing it.
