# Console compatibility

| Console | Available input | In-app console session |
| --- | --- | --- |
| Xbox Series X and Series S | Camera pointed at the game on the TV. ReplayKit can read frames exposed by a compatible client. | Unimplemented. The user signs in to Microsoft's own client or browser. |
| PlayStation 4 and PlayStation 5 | Camera pointed at the game on the TV. ReplayKit can read frames exposed by a compatible client. | Unimplemented. The user signs in to Sony's own client. |

The official Xbox route documents Series X and Series S support, enabling Remote Features and using a Microsoft account. The published consumer workflow opens an Xbox client or browser. There is no documented public third-party iOS API for discovering a console, exchanging Remote Play session authorization or obtaining decoded Xbox frames. Generic Microsoft account sign-in gives an app an identity and does not by itself give it permission to use the Remote Play service. Greenlight is MIT-licensed and demonstrates Xbox home streaming with a TypeScript desktop client. A port would still depend on compatibility with undocumented Xbox services and require permission to use the relevant Microsoft authentication and streaming endpoints. GameCaption uses the supported external client route and never asks for Microsoft account credentials. [Xbox Remote Play](https://www.xbox.com/en-US/consoles/remote-play) · [Greenlight](https://github.com/unknownskl/greenlight)

Sony documents PS Remote Play for iPhone and pairing with a PS4 or PS5. The consumer workflow uses the official client and the user's PlayStation account. Sony does not document a public third-party iOS client API for discovery, pairing or video reception. Chiaki-ng is an AGPL-3.0 open-source implementation covering PS4 and PS5. Embedding its client would require iOS porting, license review and testing with both console generations. GameCaption links to the official setup and accepts only frames iOS makes available to a user-authorized broadcast. [PS Remote Play](https://www.playstation.com/en-us/remote-play/) · [Chiaki-ng](https://github.com/chiaki-ng/chiaki-ng)

Camera mode is independent of console authentication and video transport. It reads visible subtitles on a television without showing a Remote Play stream on iPhone. For cross-app capture, sign the app and extension and test with the actual client. A blank capture or an app that stops playback during recording may require camera mode.

## Device verification

- On an iPhone 14 Pro Max with iOS 27, install a correctly signed IPA. Verify startup, portrait layout, image import from Files and Photos, microphone permissions, offline language preparation and speech playback.
- On a TV, turn on English subtitles and try a two-line caption, a duplicate, a new caption and several seconds without text. Verify the selected crop and check that the phone and browser clear the caption. Repeat on Xbox and PlayStation.
- For each official Remote Play client, separately verify sign-in and connection, then start GameCaption's system broadcast with consent. Check the frame OCR status, foreground-to-background transition, orientation, pause and stop. Device and client capture permissions determine which frames reach GameCaption.
- For OBS, check the browser source transparency, alignment, subtitle updates and clearing after disconnect on the intended compositor and display.
