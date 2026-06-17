/// Configuration options for Azure Communication Services UI Library
library;

import 'package:flutter/material.dart';

/// Localization options for UI Library composites
class AcsLocalizationOptions {
  /// The locale to use for the UI Library
  final Locale locale;

  /// Optional custom layout direction
  final bool? isRightToLeft;

  const AcsLocalizationOptions({
    required this.locale,
    this.isRightToLeft,
  });

  Map<String, dynamic> toMap() => {
        'languageCode': locale.languageCode,
        'countryCode': locale.countryCode,
        'isRightToLeft': isRightToLeft,
      };
}

/// Theme options for UI Library composites
class AcsThemeOptions {
  /// Primary color for the UI
  final Color? primaryColor;

  /// Foreground color on primary
  final Color? foregroundOnPrimaryColor;

  /// Camera button color when on
  final Color? cameraOnColor;

  /// Camera button color when off
  final Color? cameraOffColor;

  const AcsThemeOptions({
    this.primaryColor,
    this.foregroundOnPrimaryColor,
    this.cameraOnColor,
    this.cameraOffColor,
  });

  Map<String, dynamic> toMap() => {
        'primaryColor': primaryColor?.toARGB32(),
        'foregroundOnPrimaryColor': foregroundOnPrimaryColor?.toARGB32(),
        'cameraOnColor': cameraOnColor?.toARGB32(),
        'cameraOffColor': cameraOffColor?.toARGB32(),
      };
}

/// Multitasking options for CallComposite (Android/iOS)
class AcsMultitaskingOptions {
  /// Enable multitasking (background mode)
  final bool enableMultitasking;

  /// Enable Picture-in-Picture when multitasking
  final bool enablePictureInPicture;

  const AcsMultitaskingOptions({
    this.enableMultitasking = true,
    this.enablePictureInPicture = true,
  });

  Map<String, dynamic> toMap() => {
        'enableMultitasking': enableMultitasking,
        'enablePictureInPicture': enablePictureInPicture,
      };
}

/// Call orientation options
enum AcsCallOrientation {
  portrait,
  landscape,
  landscapeRight,
  landscapeLeft,
  allButUpsideDown,
}

/// Options for launching CallComposite
class CallCompositeOptions {
  /// Display name for the local participant
  final String displayName;

  /// Theme options
  final AcsThemeOptions? theme;

  /// Localization options
  final AcsLocalizationOptions? localization;

  /// Multitasking options
  final AcsMultitaskingOptions? multitasking;

  /// Enable/disable camera button
  final bool enableCameraButton;

  /// Enable/disable microphone button
  final bool enableMicrophoneButton;

  /// Skip the setup screen and join call directly
  final bool skipSetupScreen;

  /// Initial camera state (on/off)
  final bool cameraOn;

  /// Initial microphone state (on/off)
  final bool microphoneOn;

  /// Orientation lock for the call
  final AcsCallOrientation? orientation;

  const CallCompositeOptions({
    required this.displayName,
    this.theme,
    this.localization,
    this.multitasking,
    this.enableCameraButton = true,
    this.enableMicrophoneButton = true,
    this.skipSetupScreen = false,
    this.cameraOn = false,
    this.microphoneOn = false,
    this.orientation,
  });

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'theme': theme?.toMap(),
        'localization': localization?.toMap(),
        'multitasking': multitasking?.toMap(),
        'enableCameraButton': enableCameraButton,
        'enableMicrophoneButton': enableMicrophoneButton,
        'skipSetupScreen': skipSetupScreen,
        'cameraOn': cameraOn,
        'microphoneOn': microphoneOn,
        'orientation': orientation?.name,
      };
}

/// Options for launching ChatComposite
class ChatCompositeOptions {
  /// Display name for the local participant
  final String displayName;

  /// Theme options
  final AcsThemeOptions? theme;

  /// Localization options
  final AcsLocalizationOptions? localization;

  const ChatCompositeOptions({
    required this.displayName,
    this.theme,
    this.localization,
  });

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'theme': theme?.toMap(),
        'localization': localization?.toMap(),
      };
}
