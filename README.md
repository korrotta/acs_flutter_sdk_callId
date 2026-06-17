# Azure Communication Services Flutter SDK

A Flutter plugin that wraps Microsoft Azure Communication Services (ACS), enabling token-based voice/video calling, chat, and pre-built UI composites in Flutter applications.

[![pub package](https://img.shields.io/pub/v/acs_flutter_sdk.svg)](https://pub.dev/packages/acs_flutter_sdk)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

### Custom UI (AcsFlutterSdk)
Build your own calling interfaces with full control:

- ✅ **Token-based initialization** for ACS Calling SDK
- ✅ **Audio calling controls**: start, join, mute/unmute, and hang up ACS calls
- ✅ **Video support**: start/stop local video, switch cameras, and render platform-native preview/remote streams
- ✅ **Mid-call participant management**: invite or remove participants during calls
- ✅ **Teams meeting interop**: join Microsoft 365 Teams meetings by URL

### UI Library (AcsUiLibrary)
Use pre-built, production-ready UI composites with minimal code:

- ✅ **CallComposite**: Complete calling UI with setup screen, participant gallery, and controls
- ✅ **Multiple call types**: Group calls, Teams meetings, Rooms, and 1:1/1:N calls
- ✅ **Localization**: 20+ languages built-in (English, Spanish, French, German, Arabic, etc.)
- ✅ **Theming**: Customize primary colors and branding
- ✅ **Picture-in-Picture**: Multitasking support on both platforms
- ✅ **Accessibility**: Built-in A11y compliance

### Common Features
- ⚠️ **Identity management**: Development helpers only—production flows must run on your backend
- ✅ **Cross-platform**: Supports Android (API 24+) and iOS (13.0+)

## ⚠️ Important Notice: Chat Module Removed

**The Chat SDK has been removed starting from version 0.2.3** to significantly reduce app size and improve performance.

**Why was chat removed?**
- The Azure Communication Services Chat SDK added substantial size to the application bundle
- Most applications use calling features more frequently than chat
- Removing chat reduced the overall SDK footprint

**Alternatives for chat functionality:**
- For pre-built chat UI, consider implementing server-side chat using the Azure Communication Services REST APIs
- Use third-party chat solutions (Firebase, Stream Chat, etc.) if chat is a critical requirement
- The calling features remain fully functional and are the primary focus of this SDK

If you require chat functionality, please stay on version 0.2.2 or earlier. Note that older versions will not receive updates or bug fixes.

## Platform Support

| Platform | Supported | Minimum Version |
|----------|-----------|----------------|
| Android  | ✅        | API 24 (Android 7.0) |
| iOS      | ✅        | iOS 13.0+ |

## Getting Started

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  acs_flutter_sdk: ^0.2.4
```

Then run:

```bash
flutter pub get
```

### Platform Setup

#### Android

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

Ensure your `android/app/build.gradle` has minimum SDK version 24:

```gradle
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

#### iOS

Add the following to your `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for calls</string>
```

Ensure your `ios/Podfile` has minimum iOS version 13.0:

```ruby
platform :ios, '13.0'
```

## Usage

This SDK offers two approaches for integrating Azure Communication Services:

| Approach | Best For | Effort |
|----------|----------|--------|
| **UI Library** (`AcsUiLibrary`) | Quick deployment, standard UI needs | Low - hours |
| **Custom UI** (`AcsFlutterSdk`) | Full customization, unique designs | High - weeks |

---

### UI Library Approach (Recommended for Quick Start)

Launch pre-built calling UI with just a few lines of code:

```dart
import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';

final uiLibrary = AcsUiLibrary();

// Set up event handlers
uiLibrary.onCallStateChanged = (event) => print('State: ${event.state}');
uiLibrary.onDismissed = (event) => print('Call ended');

// Launch a group call with full UI
await uiLibrary.launchGroupCall(
  accessToken: 'your-access-token',
  groupId: 'your-group-uuid',
  options: CallCompositeOptions(
    displayName: 'John Doe',
    cameraOn: true,
    microphoneOn: true,
  ),
);

// Or join a Teams meeting
await uiLibrary.launchTeamsMeeting(
  accessToken: 'your-access-token',
  meetingLink: 'https://teams.microsoft.com/l/meetup-join/...',
  options: CallCompositeOptions(
    displayName: 'Guest User',
    theme: AcsThemeOptions(primaryColor: Colors.blue),
    localization: AcsLocalizationOptions(locale: Locale('es', 'ES')),
  ),
);
```

---

### Custom UI Approach (Full Control)

Build your own UI with granular control over every aspect:

```dart
import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';

// Initialize the SDK
final sdk = AcsFlutterSdk();
```

#### Identity Management

> ℹ️ Production guidance: ACS identity creation and token issuance must happen on a secure backend. The plugin only exposes a lightweight initialization helper so the native SDKs can be configured during development.

```dart
// Create an identity client
final identityClient = sdk.createIdentityClient();

// Initialize with your connection string (local development only)
await identityClient.initialize('your-connection-string');

// For production:
// 1. Your app requests a token from your backend.
// 2. The backend uses an ACS Communication Identity SDK to create users and tokens.
// 3. The backend returns the short-lived token to your app.
// 4. The app passes the token into the calling/chat clients shown below.
```

#### Voice & Video Calling

```dart
// Create a calling client
final callingClient = sdk.createCallClient();

// Initialize with an access token (obtained from your backend)
await callingClient.initialize('your-access-token');

// Request camera/microphone permissions before starting video calls
await callingClient.requestPermissions();

// Start a call to one or more participants
final call = await callingClient.startCall(
  ['user-id-1', 'user-id-2'],
  withVideo: true,
);

// Join an existing group call
final joined = await callingClient.joinCall('group-call-id', withVideo: true);

// Join a Microsoft Teams meeting using the meeting link
final teamsCall = await callingClient.joinTeamsMeeting(
  'https://teams.microsoft.com/l/meetup-join/...',
  withVideo: false,
);

// Mute/unmute audio
await callingClient.muteAudio();
await callingClient.unmuteAudio();

// Start/stop local video and switch cameras
await callingClient.startVideo();
await callingClient.switchCamera();
await callingClient.stopVideo();

// Invite or remove participants during an active call
await callingClient.addParticipants(['user-id-3']);
await callingClient.removeParticipants(['user-id-2']);

// End the call
await callingClient.endCall();

// Listen to call state changes
callingClient.callStateStream.listen((state) {
  print('Call state: $state');
});
```

Embed the platform-rendered video views in your widget tree:

```dart
const SizedBox(height: 160, child: AcsLocalVideoView());
const SizedBox(height: 240, child: AcsRemoteVideoView());
```

#### Joining Teams Meetings

- Call `initialize` with a **valid ACS access token** before attempting to join. Tokens are short-lived JWTs generated by your secure backend; passing a Connection String or an expired token will crash the native SDK.
- Only **Microsoft 365 (work or school) Teams meetings** are supported. Consumer “Teams for Life” meetings are not currently interoperable and will return `Teams for life meeting join not supported`.
- Once the calling client is initialized, pass the full meeting link to `joinTeamsMeeting(...)`. You can opt in to start with local video by setting `withVideo: true`.

## Architecture

This plugin uses Method Channels for communication between Flutter (Dart) and native platforms:

```
┌───────────────────────────────────────────────────────┐
│                   Flutter (Dart)                       │
│  ┌────────────────────┐    ┌────────────────────┐    │
│  │  AcsFlutterSdk     │    │   AcsUiLibrary     │    │
│  │  (Custom UI)       │    │   (UI Composites)  │    │
│  │  ┌──────────────┐  │    │  ┌──────────────┐  │    │
│  │  │ CallClient   │  │    │  │CallComposite │  │    │
│  │  │IdentityClient│  │    │  └──────────────┘  │    │
│  │  └──────────────┘  │    └────────────────────┘    │
│  └────────────────────┘                               │
└────────────┬──────────────────────┬───────────────────┘
             │ acs_flutter_sdk      │ acs_ui_library
┌────────────┴──────────────────────┴───────────────────┐
│              Native Platform Code                      │
│  ┌─────────────────────────────────────────────────┐  │
│  │  Android: Calling SDK, UI Library               │  │
│  │  iOS:     Calling SDK, UI Library               │  │
│  └─────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────┘
```

## Security Best Practices

1. **Never expose connection strings in client apps**: Connection strings should only be used server-side
2. **Implement token refresh**: Access tokens expire and should be refreshed through your backend
3. **Use server-side identity management**: Create users and generate tokens on your backend
4. **Validate permissions**: Ensure users have appropriate permissions before granting access
5. **Secure token storage**: Store tokens securely using platform-specific secure storage

## Example App

A complete example application is included in the `example/` directory. To run it:

```bash
cd example
flutter run
```

## Troubleshooting

### Android Build Issues

If you encounter build issues on Android:

1. Ensure `minSdkVersion` is set to 24 or higher
2. Check that you have the latest Android SDK tools
3. Clean and rebuild: `flutter clean && flutter pub get`

### iOS Build Issues

If you encounter build issues on iOS:

1. Ensure iOS deployment target is 13.0 or higher
2. Run `pod install` in the `ios/` directory
3. Clean and rebuild: `flutter clean && flutter pub get`

### Permission Issues

Ensure all required permissions are added to your platform-specific configuration files as described in the Platform Setup section.
On Android 6.0+ and iOS 10+, request camera/microphone permissions at runtime before starting calls (e.g. with [`permission_handler`](https://pub.dev/packages/permission_handler)).

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Documentation

- [API Reference](https://pub.dev/documentation/acs_flutter_sdk/latest/) - Full API documentation on pub.dev

## Acknowledgments

- Built on top of [Azure Communication Services](https://azure.microsoft.com/en-us/services/communication-services/)
- Uses the official Azure Communication Services SDKs and UI Library for Android and iOS

## Support

For issues and feature requests, please file an issue on [GitHub](https://github.com/BurhanRabbani/acs_flutter_sdk/issues).

For Azure Communication Services specific questions, refer to the [official documentation](https://docs.microsoft.com/en-us/azure/communication-services/).
