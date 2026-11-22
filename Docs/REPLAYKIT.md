# ReplayKit Screen Captions (GameCaption 0.3.0)

## Implemented
- SwiftUI broadcast picker selects the GameCaption Broadcast Upload extension.
- Broadcast sample handler receives video frames after explicit system approval; OCR uses Apple Vision.
- On iOS 26+, non-UI Apple TranslationSession tries to translate using **already-installed** language packs. It cannot download language packs in the extension. Failures show a status instead of fake translation.
- Source, translation, status, and language pair are transferred via App Group UserDefaults.
- Captured raw frames are not persisted or sent to any external backend.

## Platform constraints and signing
- Requires signed app and embedded extension with a provisioning profile authorizing the **same App Group**: `group.com.tmoath07.gamecaption`. Unsigned GitHub IPA is only a build artifact; an arbitrary ESign certificate does not guarantee App Groups entitlement.
- ReplayKit only captures after the user opts in. Protected content can be unavailable or blank.
- iOS 18–25: OCR only in the extension; iOS 26+: translation attempted with preinstalled Apple language packs.
- The main app may be suspended when another application is foregrounded. The broadcast extension can process frames independently, but a web server inside the main app cannot be assumed to remain available in the background.
- No direct Xbox / PlayStation Remote Play protocol is implemented. Users can independently run compatible Remote Play clients, but screen capture is not a substitute for native streaming support.
- An iPhone app cannot draw over a console's independent HDMI input on a television. That requires a display/browser that supports independent overlay/PiP or a separate video compositor.
- Hardware validation is still required: ReplayKit broadcast from a real iPhone, translation runtime, and ESign/install permissions cannot be established by Xcode build alone.

## How to test on a physical iPhone (signed with proper entitlements)
1. In iOS Translate settings, install the language packs (e.g. English and Arabic).
2. Open GameCaption → 'شاشة', choose languages, tap the system broadcast picker and consent.
3. Switch to your own Remote Play app. The extension captures available (non-protected) screen frames.
4. Return to GameCaption to see the latest text/translation or error. To stop, stop broadcasting from iOS's recording control.

## Licensing
Only Apple's system frameworks and original source are used. No Side Screen proprietary assets, code, models, or decryption material are present.
