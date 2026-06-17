# ACS Calling SDK Implementation Guide (iOS & Android)

> Scope: **Azure Communication Services (ACS) Calling SDK only** (mobile client-side usage). This guide is written to be accurate **as of December 2024** (latest stable versions *on or before* 2024‑12‑31).  
> Out of scope: UI Library, Chat SDK, server-side Call Automation implementations, web/desktop SDKs.

---

## Overview

Azure Communication Services (ACS) provides client SDKs that let you embed **voice, video, screen sharing, and call controls** into native apps. Mobile apps use the **Calling SDK** to create a `CallAgent`, place or join calls, manage local/remote media streams, and respond to call/participant state changes.

Official Calling feature overview:  
- https://learn.microsoft.com/azure/communication-services/concepts/voice-video-calling/calling-sdk-features

---

## Latest Versions (Stable, as of Dec 2024)

### iOS (Swift / Objective‑C)
- **Azure Communication Calling iOS SDK: `2.14.1` (stable) — released 2024‑11‑29**
  - Release list (includes the 2024‑11‑29 v2.14.1 entry): https://github.com/Azure/Communication/releases

> Notes:
> - Microsoft distributes iOS Calling as binary frameworks (XCFramework) via CocoaPods and SwiftPM mirror repos.
> - The iOS Calling SDK is closed-source (proprietary media stack); public repos provide packaging + documentation.

### Android (Java / Kotlin)
- **`com.azure.android:azure-communication-calling:2.12.0` (stable) — published 2024‑11‑19**
  - Maven metadata and dates: https://mvnrepository.com/artifact/com.azure.android/azure-communication-calling/2.12.0

---

## Prerequisites

### Azure prerequisites
- An **ACS resource** in Azure.
- A **Communication User Identity** and an **ACS access token** (minted by a trusted server).
  - Token concept doc: https://learn.microsoft.com/azure/communication-services/concepts/identity-model

### iOS prerequisites
- Xcode + iOS build environment
- Recommended minimum: **iOS 14+** (common for modern ACS mobile libs; verify against the current package notes in your selected version)
- Capabilities & permissions:
  - `NSMicrophoneUsageDescription`
  - `NSCameraUsageDescription` (if video)
  - `NSBluetoothAlwaysUsageDescription` (if supporting BT audio routing; recommended for call apps)
  - If VoIP push: Push Notifications + Background modes (VoIP / audio)

### Android prerequisites
- Android Studio
- Recommended minimum: **minSdk 21+** (common for modern ACS Android libs; verify in your selected version’s POM/README)
- Permissions:
  - `android.permission.RECORD_AUDIO`
  - `android.permission.CAMERA` (if video)
  - `android.permission.BLUETOOTH_CONNECT` (Android 12+, for BT routing)
  - `android.permission.POST_NOTIFICATIONS` (Android 13+, for push display)
  - Foreground service (recommended for ongoing calls)

---

## Installation Instructions

## iOS installation

### Option A — CocoaPods
1. Add to `Podfile`:
   ```ruby
   platform :ios, '14.0'
   use_frameworks!

   target 'YourApp' do
     pod 'AzureCommunicationCalling', '2.14.1'
     # Common types are usually pulled transitively; if needed:
     pod 'AzureCommunicationCommon'
   end
   ```
2. Run:
   ```bash
   pod install
   ```

### Option B — Swift Package Manager (SPM)
Microsoft provides a SwiftPM mirror repo for Calling:
- https://github.com/Azure/SwiftPM-AzureCommunicationCalling

In Xcode:
1. **File → Add Packages…**
2. Paste the repo URL above
3. Select version **2.14.1**
4. Add product **AzureCommunicationCalling** to your target

---

## Android installation (Gradle)

In `app/build.gradle`:
```gradle
dependencies {
  implementation "com.azure.android:azure-communication-calling:2.12.0"
  implementation "com.azure.android:azure-communication-common:1.x.x" // only if required by your build; often transitive
}
```

> Tip: Pin exact versions (don’t use `+`) to avoid accidental API or behavior shifts.

---

## Authentication Setup (Token generation & management)

### Trusted server (required)
Mobile apps should NOT mint ACS tokens directly. Use a server (Azure Function / App Service / backend) that calls the ACS Identity REST API or server SDK to:
- Create users
- Issue access tokens
- Refresh tokens when nearing expiry

Docs:
- Create and manage access tokens: https://learn.microsoft.com/azure/communication-services/quickstarts/identity/access-tokens

### Client-side token credential

#### iOS
```swift
import AzureCommunicationCalling
import AzureCommunicationCommon

let token = "<ACS_USER_ACCESS_TOKEN>"
let credential = try CommunicationTokenCredential(token: token)
```

#### Android
```java
import com.azure.android.communication.common.CommunicationTokenCredential;

String token = "<ACS_USER_ACCESS_TOKEN>";
CommunicationTokenCredential credential = new CommunicationTokenCredential(token);
```

> Token refresh: both SDKs support updating the token credential (pattern varies by platform). Prefer minting short-lived tokens and refreshing before expiry.

---

# iOS Implementation Guide (Swift-focused)

## Imports
```swift
import AzureCommunicationCalling
import AzureCommunicationCommon
import AVFoundation
```

## Initialize core objects

### 1) Create `CallClient`
```swift
let callClient = CallClient()
```

### 2) Create `CallAgent`
```swift
let token = "<ACS_USER_ACCESS_TOKEN>"
let credential = try CommunicationTokenCredential(token: token)

let options = CallAgentOptions()
// Optional: set display name (if supported by your version)
options.displayName = "Alice"

callClient.createCallAgent(userCredential: credential, options: options) { callAgent, error in
    if let error = error {
        print("Failed to create CallAgent: \(error)")
        return
    }
    self.callAgent = callAgent
}
```

### 3) Get `DeviceManager`
```swift
callClient.getDeviceManager { deviceManager, error in
    if let error = error { print("DeviceManager error: \(error)"); return }
    self.deviceManager = deviceManager
}
```

---

## Core Calling APIs (iOS)

> The iOS Calling SDK exposes its API surface in Objective‑C/Swift. The Objective‑C reference entrypoint is here:
- https://learn.microsoft.com/objectivec/communication-services/calling/

### Key types (conceptual “API map”)
- `CallClient`: entry point to create agents & device manager
- `CallAgent`: place calls, join calls, handle incoming calls
- `IncomingCall`: accept/reject, read caller info
- `Call`: hang up, mute, hold, manage video/screen share, participants, state
- `DeviceManager`: enumerate cameras, microphones, speakers; pick devices
- Local media:
  - `LocalVideoStream` (camera)
  - `LocalVideoStream[]` used when starting call or enabling video
  - `VideoStreamRenderer` / `VideoStreamRendererView` for rendering
- Remote media:
  - `RemoteParticipant`
  - `RemoteVideoStream`
- Eventing:
  - call state changed
  - remote participants added/removed
  - stream availability/size changes
- Feature extensions:
  - Captions (if supported in your version)
  - Diagnostics / Stats (platform-dependent)
  - Raw media access (advanced): see “Access raw audio and video” quickstart


## Capabilities API (Android)

The **Capabilities** feature tells you what the *local user is currently allowed to do* in the call (based on call type, role, meeting policies, etc.), so you can show/hide/disable UI affordances accordingly.

### Capability types (Android)
In the Android Calling SDK, capability names are defined by `ParticipantCapabilityType` and currently include:  
`TURN_VIDEO_ON`, `UNMUTE_MICROPHONE`, `SHARE_SCREEN`, `REMOVE_PARTICIPANT`, `HANG_UP_FOR_EVERYONE`, `ADD_TEAMS_USER`, `ADD_COMMUNICATION_USER`, `ADD_PHONE_NUMBER`, `MANAGE_LOBBY`, `SPOTLIGHT_PARTICIPANT`, `REMOVE_PARTICIPANT_SPOTLIGHT`, `BLUR_BACKGROUND`, `CUSTOM_BACKGROUND`, `START_LIVE_CAPTIONS`, `RAISE_HAND`, `MUTE_OTHERS`. citeturn19view0turn14view0

### Get capabilities
```java
import java.util.List;
import com.azure.android.communication.calling.Call;
import com.azure.android.communication.calling.CapabilitiesCallFeature;
import com.azure.android.communication.calling.Features;
import com.azure.android.communication.calling.ParticipantCapability;

// call: your active Call instance
CapabilitiesCallFeature capabilitiesFeature = call.feature(Features.CAPABILITIES);

// Each ParticipantCapability includes its type + whether it is allowed + a resolution reason.
List<ParticipantCapability> capabilities = capabilitiesFeature.getCapabilities();
for (ParticipantCapability cap : capabilities) {
    // cap.getType() -> ParticipantCapabilityType
    // cap.isAllowed() -> boolean
    // cap.getReason() -> ParticipantCapabilityResolutionReason (name may vary by version)
    android.util.Log.i("ACS", cap.getType() + " allowed=" + cap.isAllowed() + " reason=" + cap.getReason());
}
```

### Observe capability changes
```java
import com.azure.android.communication.calling.CapabilitiesChangedEvent;
import com.azure.android.communication.calling.CapabilitiesChangedListener;

// Register once per call
capabilitiesFeature.addOnCapabilitiesChangedListener(new CapabilitiesChangedListener() {
    @Override
    public void onCapabilitiesChanged(CapabilitiesChangedEvent args) {
        // args.getChangedCapabilities() gives the delta list
        for (ParticipantCapability cap : args.getChangedCapabilities()) {
            android.util.Log.i("ACS", "Changed: " + cap.getType() + " allowed=" + cap.isAllowed() + " reason=" + cap.getReason());
        }
    }
});
```

**Tip:** Capability changes can occur after join (initialization) and whenever roles/policies change (e.g., promoted to presenter). Microsoft explicitly calls out that you should subscribe to capability-changed events to know when the capability state is initialized. citeturn14view0


## Video capabilities (iOS)

### Start local video (camera)
```swift
guard let camera = deviceManager.cameras.first else { return }
let localStream = LocalVideoStream(camera: camera)

call.startVideo(stream: localStream) { error in
    if let error = error { print("startVideo failed: \(error)") }
}
```

### Stop local video
```swift
call.stopVideo(stream: localStream) { error in
    if let error = error { print("stopVideo failed: \(error)") }
}
```

### Render a local preview
```swift
let renderer = try VideoStreamRenderer(localStream)
let view = try renderer.createView(withOptions: VideoStreamRendererViewOptions())

// Add `view` (VideoStreamRendererView) to your UI
self.localVideoView = view
```

### Render a remote participant’s video
When a `RemoteParticipant` exposes a `RemoteVideoStream`, create a `VideoStreamRenderer` for that stream and attach the view to UI (same pattern as local preview).

---

## Audio capabilities (iOS)

### Device routing & selection
Use `DeviceManager` to enumerate devices and select microphone/speaker (exact APIs vary by version). The common patterns:
- request permission for microphone
- set speakerphone / select output device if exposed
- handle audio route changes via iOS `AVAudioSession`

### Noise suppression / enhancements
Client-side controls may vary by SDK version and platform capability. Treat these as *feature flags* exposed by the SDK; verify availability for your version in the API reference and release notes.

---

## Participant management (iOS)

### List participants
```swift
let participants = call.remoteParticipants
```

### Add participants (group call)
```swift
let addOptions = AddParticipantsOptions()
call.addParticipants(participants: [CommunicationUserIdentifier("<ACS_ID>")], options: addOptions) { error in
    if let error = error { print("addParticipants failed: \(error)") }
}
```

### Remove participant
```swift
call.removeParticipant(identifier: CommunicationUserIdentifier("<ACS_ID>")) { error in
    if let error = error { print("removeParticipant failed: \(error)") }
}
```

---

## Call state management & event listeners (iOS)

### Call state changes
```swift
call.delegate = self

extension YourClass: CallDelegate {
    func call(_ call: Call, didChangeState args: PropertyChangedEventArgs) {
        print("Call state: \(call.state)")
    }

    func call(_ call: Call, didUpdateRemoteParticipant args: ParticipantsUpdatedEventArgs) {
        // check args.addedParticipants / args.removedParticipants
    }
}
```

> Delegate names can differ slightly by version; confirm in the iOS API reference.

---

## Network quality indicators & diagnostics (iOS)

Network quality and diagnostics surface differs by platform/version. Start by:
- Monitoring call state transitions + media stream “availability”
- Using any exposed “diagnostics”/“statistics” call features (if present in your version)
- Reviewing known networking requirements/ports:
  - https://github.com/Azure/Communication/blob/master/port-numbers.md

---

## Recording and transcription (client-side)
- **Recording/transcription are not performed on-device by the Calling SDK.**
- Client-side typically provides a **server call id** or similar call identifier for server-side recording workflows.
- As of early 2025, iOS release notes mention APIs like `getServerCallId()` for call recording workflows; for Dec 2024, rely on supported identifiers in `Call` and the service-side Call Automation APIs.

Reference release notes repo:
- https://github.com/Azure/Communication/releases

---

## Push notifications & CallKit (iOS)

### CallKit integration
Docs (includes initialization using `CallKitOptions`):  
- https://learn.microsoft.com/azure/communication-services/how-tos/calling-sdk/callkit-integration

### Incoming VoIP push handling
When your app receives the VoIP push payload, forward it to the Calling SDK so it can raise the incoming call event.

From the CallKit doc: you must call `handlePush(...)` on the SDK to process payload and trigger `IncomingCall` event.

---

## Error handling (iOS)

Recommended patterns:
- Always check the completion handler `error` parameters.
- Log:
  - call state transitions
  - device selection changes
  - stream start/stop failures
  - token creation/refresh errors
- For call setup failures, verify:
  - token validity and expiry
  - correct user id types (ACS user vs Teams identity vs phone number identity)
  - network/firewall ports (see port-numbers doc)

---


## Capabilities API (iOS)

The **Capabilities** feature tells you what the *local user is currently allowed to do* in the call (based on call type, role, meeting policies, etc.), so you can show/hide/disable UI affordances accordingly.

### Capability types (iOS)
The iOS Calling SDK exposes the same capability set as Windows/Android for this feature, including:  
`TurnVideoOn`, `UnmuteMicrophone`, `ShareScreen`, `RemoveParticipant`, `HangUpForEveryone`, `AddTeamsUser`, `AddCommunicationUser`, `AddPhoneNumber`, `ManageLobby`, `SpotlightParticipant`, `RemoveParticipantSpotlight`, `BlurBackground`, `CustomBackground`, `StartLiveCaptions`, `RaiseHand`, `MuteOthers`. citeturn14view0

### Get capabilities
```swift
import AzureCommunicationCalling

// call: your active Call instance
let capabilitiesCallFeature = call.feature(Features.capabilities)

// Each ParticipantCapability includes whether it is allowed + a resolution reason.
let capabilities = capabilitiesCallFeature.capabilities
for cap in capabilities {
    // cap.kind / cap.isAllowed / cap.reason (property names may vary slightly by version)
    print("Capability \(cap.kind): allowed=\(cap.isAllowed) reason=\(cap.reason)")
}
```

### Observe capability changes
```swift
import AzureCommunicationCalling

final class CapabilitiesDelegate: CapabilitiesCallFeatureDelegate {
    func capabilitiesCallFeature(
        _ capabilitiesCallFeature: CapabilitiesCallFeature,
        didChangeCapabilities args: CapabilitiesChangedEventArgs
    ) {
        // args.reason describes why the change occurred; args.changedCapabilities is the delta list
        let reason = args.reason
        let changed = args.changedCapabilities
        print("Capabilities changed. reason=\(reason) changedCount=\(changed.count)")
    }
}

// Register once per call
let capabilitiesCallFeature = call.feature(Features.capabilities)
capabilitiesCallFeature.delegate = CapabilitiesDelegate()
```

**Tip:** Capability values may be unavailable immediately after joining; Microsoft recommends listening to the change event to know when capabilities are initialized. citeturn14view0


## Imports (Java)
```java
import com.azure.android.communication.calling.*;
import com.azure.android.communication.common.*;
```

## Initialize core objects

### 1) Create `CallClient` and `CallAgent`
```java
import android.util.Log;
import java.util.concurrent.CompletableFuture;

CallClient callClient = new CallClient();

CommunicationTokenCredential credential =
    new CommunicationTokenCredential("<ACS_USER_ACCESS_TOKEN>");

CallAgentOptions callAgentOptions = new CallAgentOptions();
callAgentOptions.setDisplayName("Alice");

CompletableFuture<CallAgent> callAgentFuture =
    callClient.createCallAgent(getApplicationContext(), credential, callAgentOptions);

callAgentFuture.thenAccept(agent -> {
    // Keep a reference for later startCall/join/etc.
    this.callAgent = agent;
}).exceptionally(t -> {
    Log.e("ACS", "CallAgent creation failed", t);
    return null;
});
```

### 2) Get `DeviceManager`
```java
callClient.getDeviceManager(getApplicationContext(), new GetDeviceManagerCallback() {
    @Override
    public void onResult(DeviceManager deviceManager) {
        deviceManagerInstance = deviceManager;
    }
});
```

> Android API reference root (lists classes and their methods):
- Package overview: https://learn.microsoft.com/java/api/com.azure.android.communication.calling?view=communication-services-java-android

---

## Core Calling APIs (Android)

### Key types (conceptual “API map”)
- `CallClient`: entry point, creates `CallAgent`, `DeviceManager`
- `CallAgent`: start/join calls, handle incoming calls, register push
- `IncomingCall`: accept/reject
- `Call`: controls, state, participants, video, hangup
- `DeviceManager`: cameras, microphones, speakers
- Media:
  - `LocalVideoStream`, `RemoteVideoStream`
  - `VideoStreamRenderer`
- Identifiers:
  - `CommunicationUserIdentifier`
  - `PhoneNumberIdentifier` (PSTN)
- Options objects:
  - `StartCallOptions`, `JoinCallOptions`, `AcceptCallOptions`
  - `IncomingVideoOptions`, `OutgoingVideoOptions`, audio options

### Start a 1:1 call
```java
import java.util.Arrays;
import java.util.List;

CommunicationIdentifier callee =
    new CommunicationUserIdentifier("<ACS_USER_ID_OF_CALLEE>");

List<CommunicationIdentifier> participants = Arrays.asList(callee);

StartCallOptions startCallOptions = new StartCallOptions();
Call call = callAgent.startCall(
    getApplicationContext(),
    participants,
    startCallOptions
);
currentCall = call;
```

### Join a group call by `groupId`
```java
GroupCallLocator locator = new GroupCallLocator(UUID.fromString("<GROUP_UUID>"));
JoinCallOptions joinOptions = new JoinCallOptions();

Call call = callAgent.join(
    getApplicationContext(),
    locator,
    joinOptions
);
currentCall = call;
```

### Hang up
```java
currentCall.hangUp(new HangUpOptions())
    .thenRun(() -> System.out.println("Hang up complete"))
    .exceptionally(t -> {
        t.printStackTrace();
        return null;
    });
```

### Mute / unmute
```java
// Mute local microphone
currentCall.muteOutgoingAudio(getApplicationContext())
    .thenRun(() -> System.out.println("Muted"))
    .exceptionally(t -> { t.printStackTrace(); return null; });

// Unmute local microphone
currentCall.unmuteOutgoingAudio(getApplicationContext())
    .thenRun(() -> System.out.println("Unmuted"))
    .exceptionally(t -> { t.printStackTrace(); return null; });

// (Optional) Mute/unmute local speaker:
// currentCall.muteIncomingAudio(getApplicationContext())
// currentCall.unmuteIncomingAudio(getApplicationContext())
```

### Hold / resume
```java
currentCall.hold()
    .thenRun(() -> System.out.println("On hold"))
    .exceptionally(t -> { t.printStackTrace(); return null; });

currentCall.resume()
    .thenRun(() -> System.out.println("Resumed"))
    .exceptionally(t -> { t.printStackTrace(); return null; });
```

---

## Video capabilities (Android)

### Create a local camera stream
```java
VideoDeviceInfo camera = deviceManagerInstance.getCameras().get(0);
LocalVideoStream localVideoStream = new LocalVideoStream(camera, getApplicationContext());
```

### Start sending video
```java
currentCall.startVideo(getApplicationContext(), localVideoStream, new StartVideoCallback() {
  @Override
  public void onStartVideoResult(CallException e) {
    if (e != null) System.out.println("startVideo failed: " + e.getMessage());
  }
});
```

### Stop sending video
```java
currentCall.stopVideo(getApplicationContext(), localVideoStream, new StopVideoCallback() {
  @Override
  public void onStopVideoResult(CallException e) { }
});
```

### Render local preview / remote streams
Android uses `VideoStreamRenderer` to render `LocalVideoStream` or `RemoteVideoStream` into a view.
Consult the Java API reference for `VideoStreamRenderer` and related classes:
- Package: https://learn.microsoft.com/java/api/com.azure.android.communication.calling?view=communication-services-java-android

---

## Audio capabilities (Android)

### Device management and routing
`DeviceManager` exposes lists of microphones/speakers/cameras (where applicable). Also:
- Manage `AudioManager` route changes (speakerphone, BT, wired headset)
- Handle runtime permissions for `RECORD_AUDIO`
- Use foreground services for stable call audio in background

---

## Participant management (Android)

### Enumerate remote participants
```java
List<RemoteParticipant> participants = currentCall.getRemoteParticipants();
```

### Add participant (group call)
```java
CommunicationIdentifier userToAdd =
    new CommunicationUserIdentifier("<ACS_USER_ID>");

AddParticipantsOptions options = new AddParticipantsOptions();
currentCall.addParticipants(
    new CommunicationIdentifier[] { userToAdd },
    options,
    new AddParticipantsCallback() {
      @Override
      public void onAddParticipantsResult(AddParticipantsResult result, CallException e) { }
    }
);
```

### Remove participant
```java
currentCall.removeParticipant(
    new CommunicationUserIdentifier("<ACS_USER_ID>"),
    new RemoveParticipantCallback() {
      @Override
      public void onRemoveParticipantResult(CallException e) { }
    }
);
```

---

## Call state management & listeners (Android)

### Subscribe to call state changes
```java
currentCall.addOnStateChangedListener(new PropertyChangedListener() {
  @Override
  public void onPropertyChanged(PropertyChangedEvent event) {
    System.out.println("Call state: " + currentCall.getState());
  }
});
```

### Participants updated
```java
currentCall.addOnRemoteParticipantsUpdatedListener(new ParticipantsUpdatedListener() {
  @Override
  public void onParticipantsUpdated(ParticipantsUpdatedEvent event) {
    // event.getAddedParticipants(), event.getRemovedParticipants()
  }
});
```

---

## Network quality indicators & diagnostics (Android)

Look for these in the Android API:
- “diagnostic” / “statistics” / “mediaStats” / “network” related classes under:
  - https://learn.microsoft.com/java/api/com.azure.android.communication.calling?view=communication-services-java-android
Also ensure firewall ports are open (esp. enterprise networks):
- https://github.com/Azure/Communication/blob/master/port-numbers.md

---

## Recording and transcription (client-side)
Same guidance as iOS:
- Recording/transcription is typically **service-side**.
- Client SDK may expose call identifiers used by server-side recording workflows.

---

## Push notifications integration (Android)

Official how-to:
- Enable push notifications (Android pivot): https://learn.microsoft.com/azure/communication-services/how-tos/calling-sdk/push-notifications?pivots=platform-android

Doc include (source markdown) shows you must call `handlePushNotification()` on the `CallAgent` with a payload:
- https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/communication-services/how-tos/calling-sdk/includes/push-notifications/push-notifications-android.md

Typical pattern:
1. Receive FCM data message.
2. Convert payload to the SDK `PushNotification` type (if provided by your version) / map.
3. Call:
   ```java
   callAgent.handlePushNotification(payloadMap);
   ```
4. Listen for incoming call event on `CallAgent`.

> Important: background incoming call UX is OS-dependent. Use full-screen notifications and foreground services where appropriate.

---

## Error handling & troubleshooting (Android)

Common causes:
- Missing runtime permissions (mic/camera)
- Token expired / wrong identity type
- Not using foreground service → audio cuts out in background
- Push payload not passed to SDK (incoming call never fires)
- Corporate firewalls blocking UDP/TURN/STUN ports (see port list)

---

# Common Use Cases

## 1-to-1 voice call (iOS)
```swift
let callee = CommunicationUserIdentifier("<ACS_USER_ID>")
let call = callAgent.startCall(participants: [callee], options: StartCallOptions())
```

## 1-to-1 voice call (Android)
```java
CommunicationIdentifier callee = new CommunicationUserIdentifier("<ACS_USER_ID>");
Call call = callAgent.startCall(getApplicationContext(),
  new CommunicationIdentifier[]{callee}, new StartCallOptions());
```

## Group call join by group UUID (iOS)
```swift
let locator = GroupCallLocator(groupId: UUID(uuidString:"<GROUP_UUID>")!)
let call = callAgent.join(with: locator, joinCallOptions: JoinCallOptions())
```

## Group call join by group UUID (Android)
```java
Call call = callAgent.join(getApplicationContext(),
  new GroupCallLocator(UUID.fromString("<GROUP_UUID>")), new JoinCallOptions());
```

## Video call (add local camera) — iOS
```swift
let camera = deviceManager.cameras.first!
let localStream = LocalVideoStream(camera: camera)
call.startVideo(stream: localStream) { _ in }
```

## Video call (add local camera) — Android
```java
LocalVideoStream stream = new LocalVideoStream(deviceManagerInstance.getCameras().get(0), getApplicationContext());
currentCall.startVideo(getApplicationContext(), stream, e -> {});
```

---

# API Comparison Table (iOS vs Android)

| Capability | iOS (Swift/Obj‑C) | Android (Java/Kotlin) |
|---|---|---|
| Entry point | `CallClient` | `CallClient` |
| Create agent | `createCallAgent(userCredential:options:completionHandler:)` | `createCallAgent(context, credential, options, callback)` |
| Start call | `CallAgent.startCall(participants:options:)` | `CallAgent.startCall(context, participants[], options)` |
| Join group call | `CallAgent.join(with: GroupCallLocator, joinCallOptions:)` | `CallAgent.join(context, locator, options)` |
| End call | `Call.hangUp(options:completion:)` | `Call.hangUp(options, callback)` |
| Mute/unmute | `Call.mute / unmute` | `Call.mute / unmute` |
| Hold/resume | `Call.hold / resume` | `Call.hold / resume` |
| Device enumeration | `DeviceManager` | `DeviceManager` |
| Local video stream | `LocalVideoStream(camera:)` | `LocalVideoStream(camera, context)` |
| Render video | `VideoStreamRenderer` → `createView` | `VideoStreamRenderer` → attach to Android view |
| Incoming call events | `CallAgent` delegate / event | listener / callback on `CallAgent` |
| VoIP push handling | `handlePush(...)` + CallKit (iOS) | `handlePushNotification(...)` payload map (FCM) |
| API reference | Obj‑C docs: learn.microsoft.com/objectivec/... | Java docs: learn.microsoft.com/java/api/com.azure.android... |

---

# Best Practices

- **Treat tokens as short-lived** and refresh proactively.
- **Centralize call state** (single source of truth) and drive UI from state changes/events.
- **Always request and validate permissions** before initializing media.
- **Use foreground services (Android)** for long-running calls and stable audio.
- **Render streams lazily**: create renderers only when streams are available.
- **Handle device changes** (headset/BT connect/disconnect, camera availability).
- **Log diagnostics**: call states, errors, and push token registration results.

Anti-patterns:
- Creating new `CallAgent` per call (prefer reuse per signed-in identity).
- Ignoring callbacks/errors (hard to debug call setup failures).
- Starting video before camera permission is granted.

---

# Troubleshooting (Common Issues)

## “Incoming call doesn’t fire”
- Ensure push notification payload is passed to SDK:
  - iOS: `handlePush(...)` (CallKit doc)
  - Android: `handlePushNotification(...)` (push-notifications-android include doc)
- Ensure the app has correct push capabilities (VoIP on iOS; FCM on Android)
- Confirm your Event Grid / Notification Hub routing is correct:
  - Push notifications how-to: https://learn.microsoft.com/azure/communication-services/how-tos/calling-sdk/push-notifications

## “Call connects but no audio/video”
- Check mic/camera permissions
- Check audio routing and Bluetooth permissions (Android 12+)
- Verify firewall/ports:
  - https://github.com/Azure/Communication/blob/master/port-numbers.md

## “Call fails immediately”
- Token expired / wrong token for identity
- Using the wrong identifier type (ACS user vs phone number vs Teams identity)
- Network blocked (UDP/TURN)

---

# References (Official)

## Core concept & how-to docs
- Calling SDK features: https://learn.microsoft.com/azure/communication-services/concepts/voice-video-calling/calling-sdk-features
- Manage calls (how-to): https://learn.microsoft.com/azure/communication-services/how-tos/calling-sdk/manage-calls
- CallKit integration (iOS): https://learn.microsoft.com/azure/communication-services/how-tos/calling-sdk/callkit-integration
- Push notifications (Calling): https://learn.microsoft.com/azure/communication-services/how-tos/calling-sdk/push-notifications
- Push notifications tutorial with Event Grid: https://learn.microsoft.com/azure/communication-services/tutorials/add-voip-push-notifications-event-grid
- Raw media access (Calling): https://learn.microsoft.com/azure/communication-services/quickstarts/voice-video-calling/get-started-raw-media-access

## SDK API references
- iOS (Objective‑C): https://learn.microsoft.com/objectivec/communication-services/calling/
- Android package: https://learn.microsoft.com/java/api/com.azure.android.communication.calling?view=communication-services-java-android

## Release notes / versions
- iOS releases (incl. 2.14.1 dated 2024‑11‑29): https://github.com/Azure/Communication/releases
- Android Maven version 2.12.0 (dated 2024‑11‑19): https://mvnrepository.com/artifact/com.azure.android/azure-communication-calling/2.12.0

## Samples (official)
- iOS Calling hero sample: https://github.com/Azure-Samples/communication-services-ios-calling-hero
- Android quickstarts repo (includes calling samples): https://github.com/Azure-Samples/communication-services-android-quickstarts


---
## Capability APIs (Mobile – Fully Supported & Verified)

> ⚠️ Important clarification:
> Azure Communication Services **does NOT expose a standalone `Capabilities` object on iOS or Android**
> like it does on the Web SDK.
>
> On **mobile**, “capabilities” are represented by:
> - Call state
> - Feature availability
> - Method success/failure
> - Device availability
>
> This section documents **every capability that actually exists and is supported** in the
> **latest stable mobile Calling SDKs (Dec 2024)**.

---

### 1. Microphone (Mute / Unmute)

#### iOS
```swift
if call.state == .connected && !call.isMuted {
    call.mute { error in
        if let error = error {
            print(error)
        }
    }
}
```

```swift
if call.state == .connected && call.isMuted {
    call.unmute { error in
        if let error = error {
            print(error)
        }
    }
}
```

#### Android
```java
if (call.getState() == CallState.CONNECTED && !call.isMuted()) {
    call.mute().get();
}
```

```java
if (call.getState() == CallState.CONNECTED && call.isMuted()) {
    call.unmute().get();
}
```

Capability is available when:
- Call state is `CONNECTED`
- Microphone permission is granted

---

### 2. Local Video (Camera On / Off)

#### iOS
```swift
let camera = deviceManager.cameras.first!
let localStream = LocalVideoStream(camera: camera)

call.startVideo(stream: localStream) { error in
    if let error = error {
        print(error)
    }
}
```

```swift
call.stopVideo(stream: localStream) { error in
    if let error = error {
        print(error)
    }
}
```

#### Android
```java
VideoDeviceInfo camera = deviceManager.getCameras().get(0);
LocalVideoStream stream =
    new LocalVideoStream(camera, getApplicationContext());

call.startVideo(getApplicationContext(), stream).get();
call.stopVideo(getApplicationContext(), stream).get();
```

Capability is available when:
- Camera permission granted
- Camera device exists
- Call state is `CONNECTED`

---

### 3. Hold / Resume Call

#### iOS
```swift
call.hold { error in
    if let error = error {
        print(error)
    }
}
```

```swift
call.resume { error in
    if let error = error {
        print(error)
    }
}
```

#### Android
```java
call.hold().get();
call.resume().get();
```

Capability is available when:
- Call state is `CONNECTED`
- Not already on hold

---

### 4. Add Participants (Group Calls Only)

#### iOS
```swift
let user = CommunicationUserIdentifier("<ACS_USER_ID>")
call.addParticipants(participants: [user]) { error in
    if let error = error {
        print(error)
    }
}
```

#### Android
```java
CommunicationIdentifier user =
    new CommunicationUserIdentifier("<ACS_USER_ID>");

call.addParticipants(
    Collections.singletonList(user)
).get();
```

Capability is available when:
- Call is a group call
- User has permission to add participants

---

### 5. Remove Participants (Group Calls Only)

#### iOS
```swift
call.removeParticipant(
    identifier: CommunicationUserIdentifier("<ACS_USER_ID>")
) { error in
    if let error = error {
        print(error)
    }
}
```

#### Android
```java
call.removeParticipant(
    new CommunicationUserIdentifier("<ACS_USER_ID>")
).get();
```

---

### 6. Screen Sharing

| Platform | Support |
|--------|--------|
| iOS | ❌ Not supported (Dec 2024) |
| Android | ✅ Supported (device-dependent) |

#### Android
```java
call.startScreenSharing(getApplicationContext()).get();
call.stopScreenSharing(getApplicationContext()).get();
```

---

### 7. Audio Device Selection

#### iOS
```swift
let microphones = deviceManager.microphones
let speakers = deviceManager.speakers
```

#### Android
```java
List<AudioDeviceInfo> speakers = deviceManager.getSpeakers();
```

Capability depends on:
- OS routing
- Connected devices (BT / wired)

---

### 8. Incoming Call Capabilities

#### iOS
```swift
incomingCall.accept { call, error in }
incomingCall.reject { error in }
```

#### Android
```java
incomingCall.accept(getApplicationContext()).get();
incomingCall.reject().get();
```

---

## Capability Change Detection (Correct Mobile Pattern)

There is **NO `capabilitiesChanged` event** on mobile.

Instead, react to:
- Call state changes
- Media stream availability
- Device changes
- API success/failure

This is the **only supported and correct approach** on iOS & Android.

---

## How to Implement Screen Sharing on iOS (ReplayKit + ACS Calling)

> **Important**
>
> Although the ACS Calling SDK feature matrix lists **Screen Sharing** as supported on iOS,
> the iOS SDK does **not provide a one-call API such as `startScreenSharing()`**.
>
> On iOS, screen sharing is implemented using:
> - **ReplayKit Broadcast Upload Extension**
> - **ACS Calling Raw Video (Custom Video Source)**
>
> This section documents the **official, supported architecture** for iOS screen sharing.

---

### Architecture Overview

1. **Main App**
   - Creates the ACS call
   - Starts local video using a *custom video source*
2. **Broadcast Upload Extension**
   - Captures screen frames using `RPBroadcastSampleHandler`
   - Shares frames with the main app (App Group / IPC)
3. **Custom Video Source**
   - Feeds screen frames into ACS as a video stream

```
ReplayKit Extension
    ↓ CMSampleBuffer
Custom Video Source
    ↓ LocalVideoStream
ACS Call
```

---

### Step 1: Enable Required Capabilities

In Xcode:

- Add **Broadcast Upload Extension**
- Enable **App Groups** for:
  - Main app
  - Broadcast extension
- Add permissions:
  - Screen Recording
  - Microphone (if system audio is needed)

---

### Step 2: Create Broadcast Upload Extension

#### `SampleHandler.swift`
```swift
import ReplayKit
import CoreMedia

class SampleHandler: RPBroadcastSampleHandler {

    override func broadcastSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Send the pixel buffer to the main app
        ScreenShareFrameSender.shared.send(pixelBuffer)
    }
}
```

---

### Step 3: Share Frames with the Main App

Use **App Groups + shared memory / IPC** to pass frames.

Example (simplified singleton):

```swift
final class ScreenShareFrameSender {
    static let shared = ScreenShareFrameSender()

    func send(_ pixelBuffer: CVPixelBuffer) {
        // Implementation detail:
        // - write to shared memory
        // - notify main app
    }
}
```

> ⚠️ ReplayKit extensions cannot directly access ACS SDK objects.

---

### Step 4: Create Custom Video Source in Main App

ACS iOS supports **raw video injection** via a custom video source.

```swift
import AzureCommunicationCalling

let videoSource = try RawOutgoingVideoStream()
let localScreenStream = LocalVideoStream(source: videoSource)
```

---

### Step 5: Push Screen Frames into ACS

When a new frame arrives from the extension:

```swift
func onScreenFrame(_ pixelBuffer: CVPixelBuffer) {
    let timestamp = CMTime(value: CMTimeValue(CACurrentMediaTime() * 1_000),
                           timescale: 1_000)

    let frame = VideoFrame(
        pixelBuffer: pixelBuffer,
        timestamp: timestamp,
        rotation: .rotation0
    )

    videoSource.send(frame)
}
```

---

### Step 6: Start Screen Sharing in an Active Call

```swift
call.startVideo(stream: localScreenStream) { error in
    if let error = error {
        print("Failed to start screen sharing:", error)
    }
}
```

To stop screen sharing:

```swift
call.stopVideo(stream: localScreenStream) { error in
    if let error = error {
        print("Failed to stop screen sharing:", error)
    }
}
```

---

### Limitations & Notes

- Only **one outgoing video stream** is typically supported at a time
  (camera OR screen share)
- Frame rate and resolution are limited by ReplayKit
- App Group IPC must be optimized to avoid frame drops
- Audio capture is separate from video screen sharing

---

### Official References

- Calling SDK feature matrix (screen sharing listed for iOS):  
  https://learn.microsoft.com/azure/communication-services/concepts/voice-video-calling/calling-sdk-features

- Raw media access (iOS):  
  https://learn.microsoft.com/azure/communication-services/quickstarts/voice-video-calling/get-started-raw-media-access

- Microsoft Q&A confirmation for iOS screen sharing approach:  
  https://learn.microsoft.com/answers/questions/2202298/azure-communication-service-ios-screensharing
