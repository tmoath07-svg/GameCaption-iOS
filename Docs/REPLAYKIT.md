# ReplayKit screen captions

GameCaption uses Apple's broadcast picker. After you confirm the broadcast in the system UI, ReplayKit delivers available frames to the embedded extension. Vision reads the selected subtitle band, and iOS 26 or later can translate with language files already installed. The extension and app share atomic settings and caption snapshots in the App Group container. They keep the latest caption, status and heartbeat. Captured images and video are never written to storage. While GameCaption is foregrounded, the extension keeps the latest game caption available for review and skips OCR on GameCaption’s own screen. The foreground app clears obsolete captions on pause, stop or loss of updates.

1. In the GameCaption **Screen** tab, choose English and Arabic, set the subtitle region and select **Prepare offline translation languages**. The system may ask you to download language files.
2. Tap the ReplayKit system picker and approve the broadcast. Open the other app and show some subtitles. Protected content may be blank or unavailable. iOS versions before 26 can perform extension OCR and translate manually when you return to the host app.
3. Return to GameCaption to review the current caption and diagnostics. Use the system recording control to end the broadcast. The in-app LAN share is available while GameCaption is foregrounded. [Apple ReplayKit](https://developer.apple.com/documentation/replaykit) · [Apple installed translation session](https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:))

## Signing

The public IPA is unsigned. To install and use the ReplayKit workflow, configure the same Apple Developer team for the containing app and the embedded extension. The provisioning profiles must authorize these identifiers and the shared App Group.

| Target | Bundle identifier | App Group |
| --- | --- | --- |
| GameCaption | `com.tmoath07.gamecaption` | `group.com.tmoath07.gamecaption` |
| GameCaptionBroadcast | `com.tmoath07.gamecaption.BroadcastExtension` | `group.com.tmoath07.gamecaption` |

If that group or those bundle identifiers cannot be registered to your development team, use team-owned values. Update the bundle IDs in `project.yml`, the App Group in both entitlement files and `Shared/BroadcastExchange.swift`, and the picker identifier in `GameCaption/ScreenBroadcastPicker.swift`. Adjust the distribution validator to match custom identifiers if you build a custom IPA. The extension must be signed with its own matching profile before signing the containing app. Re-signing the app alone cannot grant the extension the shared container entitlement. CI verifies the configured source entitlements, the extension structure and bundle identifiers, and the unsigned build. Test installation, the picker, App Group access, and capture on a provisioned iPhone. [Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
