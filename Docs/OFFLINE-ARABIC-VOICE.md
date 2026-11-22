# GameCaption offline Arabic neural voice (0.4.0)

Source: [marwanelamami/nabra-82m-sherpa-onnx](https://huggingface.co/marwanelamami/nabra-82m-sherpa-onnx), Apache-2.0. Runtime: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), Apache-2.0.

- The IPA build fetches official, publicly licensed INT8 (lower-memory) and FP16 (higher precision) voice weights. They are functional TTS assets, **not size-padding files**.
- Swift's offline speech engine uses SherpaOnnx's Kokoro-compatible model interface to generate WAV audio on device, then plays it via AVAudioPlayer.
- Arabic text is the only supported language of this neural voice. For other languages, the existing Apple AVSpeechSynthesizer stays available.
- **This is speech output of translated text; it does not add Xbox/PS Remote Play protocols or draw on the television HDMI input.**
- Heavy model inference and resource bundling must be tested on physical iPhones. CI's compile and IPA presence checks cannot establish actual voice quality or runtime memory stability.
- The large IPA needs compatible signing of both app and ReplayKit extension, including the original App Group entitlement.
- Voice weights are downloaded from public sources by scripts/fetch_neural_voice.py, not copied from Side Screen.
- Model attribution: marwanelamami and Nabra-82M-v0.1; original license Apache 2.0; include attribution in derivative distributions.
