# Signing CUE for iPhone

Use the `iOS Signed IPA` GitHub Actions workflow to create an installable IPA
with your Apple Developer account. Do not commit certificates, provisioning
profiles, passwords, or App Store Connect keys to this repository.

## What you need

- An Apple Developer Program membership.
- Your iPhone registered in Certificates, Identifiers & Profiles.
- A unique Bundle ID, for example `com.yourname.cue`.
- An Apple Development certificate for direct development installs, or an Apple
  Distribution certificate for Ad Hoc installs.
- A matching provisioning profile for the same Bundle ID and device.

For a single iPhone, `development` signing is usually the simplest. For sharing
the IPA with registered devices, use `ad-hoc`.

## 1. Register your iPhone

1. Connect the iPhone to a Mac.
2. Open Finder or Xcode's Devices and Simulators window.
3. Copy the device UDID.
4. In the Apple Developer portal, add that UDID under **Devices**.

## 2. Create Apple signing assets

In the Apple Developer portal:

1. Create an App ID / Identifier for your Bundle ID, such as
   `com.yourname.cue`.
2. Create or download the signing certificate:
   - `Apple Development` for `development` export.
   - `Apple Distribution` for `ad-hoc` export.
3. Export the certificate and private key from Keychain Access as a `.p12`.
4. Create a provisioning profile for the same Bundle ID and your iPhone.
5. Download the `.mobileprovision` file.

## 3. Add GitHub Secrets

Go to the repository's **Settings > Secrets and variables > Actions** and add:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your 10-character Apple Team ID. |
| `BUILD_CERTIFICATE_BASE64` | Base64 of the exported `.p12`. |
| `P12_PASSWORD` | Password used when exporting the `.p12`. |
| `BUILD_PROVISION_PROFILE_BASE64` | Base64 of the `.mobileprovision`. |
| `KEYCHAIN_PASSWORD` | Any strong temporary password for CI keychain creation. |

Base64 examples:

```sh
# macOS
base64 -i certificate.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy

# Linux
base64 -w 0 certificate.p12
base64 -w 0 profile.mobileprovision
```

## 4. Run the signed build

1. Open **Actions > iOS Signed IPA**.
2. Choose **Run workflow**.
3. Enter your registered Bundle ID.
4. Select:
   - `development` with `Apple Development`, or
   - `ad-hoc` with `Apple Distribution`.
5. Wait for the workflow to finish.
6. Download the `cue-ios-signed-ipa` artifact.

The workflow validates that the provisioning profile's Team ID and Bundle ID
match the inputs before building.

## 5. Install on your iPhone

For a development or Ad Hoc IPA, use one of these Apple-supported paths:

- Apple Configurator on macOS: drag the `.ipa` onto the connected iPhone.
- Xcode Devices and Simulators: select the device and install the app.
- Finder can install some signed `.ipa` files by dragging them onto the device.

If iOS says the developer is untrusted, open **Settings > General > VPN & Device
Management** and trust your developer profile.

## Local Xcode alternative

If you prefer signing locally:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the `Runner` target.
3. Change Bundle Identifier from `app.cue` to your registered Bundle ID.
4. Select your Apple Developer Team under **Signing & Capabilities**.
5. Connect your iPhone and run the `Runner` scheme.
