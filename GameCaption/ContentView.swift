import SwiftUI
import PhotosUI
import Translation
import UniformTypeIdentifiers
import AVFoundation

private enum InputMode: String, CaseIterable, Identifiable {
    case photo = "صورة"
    case camera = "كاميرا"
    case speech = "صوت"
    case text = "نص"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .photo: return "photo.on.rectangle"
        case .camera: return "camera.viewfinder"
        case .speech: return "waveform"
        case .text: return "text.alignleft"
        }
    }
}

struct ContentView: View {
    @StateObject private var store = CaptionStore()
    @StateObject private var camera = LiveCameraScanner()
    @StateObject private var speech = LiveSpeechRecognizer()
    @StateObject private var screenServer = LocalCaptionServer()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var mode: InputMode = .photo
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var sourceCode = "en"
    @State private var targetCode = "ar"
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isReadingImage = false
    @State private var isTranslating = false
    @State private var autoTranslate = true
    @State private var scanCrop = 1.0
    @State private var errorMessage: String?
    @State private var showHistory = false
    @State private var showTV = false
    @State private var translationRequestID = UUID()
    @State private var delayedTranslation: Task<Void, Never>?
    @State private var photoPreview: UIImage?
    @State private var speaking = false
    private let speaker = AVSpeechSynthesizer()

    private struct LanguageOption: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }
    private let languages: [LanguageOption] = [
        .init(code: "en", name: "English"), .init(code: "ar", name: "العربية"),
        .init(code: "tr", name: "Türkçe"), .init(code: "es", name: "Español"),
        .init(code: "fr", name: "Français"), .init(code: "de", name: "Deutsch"),
        .init(code: "it", name: "Italiano"), .init(code: "pt", name: "Português"),
        .init(code: "ja", name: "日本語"), .init(code: "ko", name: "한국어"),
        .init(code: "zh", name: "中文")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heading
                    modePicker
                    sourceCard
                    languageCard
                    resultCard
                    toolsCard
                    privacyNote
                }
                .padding(16)
                .padding(.bottom, 22)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) { historySheet }
            .sheet(isPresented: $showTV) { tvSheet }
            .fileImporter(isPresented: $showingFileImporter,
                          allowedContentTypes: [.image, .png, .jpeg, .heic],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await readImageFile(url) }
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .onChange(of: selectedPhoto) { _, photo in
                guard let photo else { return }
                Task { await readPhoto(photo) }
            }
            .onChange(of: camera.recognizedText) { _, newText in
                guard mode == .camera, !newText.isEmpty else { return }
                updateFromLiveSource(newText)
            }
            .onChange(of: speech.transcript) { _, newText in
                guard mode == .speech, !newText.isEmpty else { return }
                updateFromLiveSource(newText)
            }
            .onChange(of: mode) { _, newMode in
                if newMode != .camera { camera.stop() }
                if newMode != .speech { speech.stop() }
                errorMessage = nil
            }
            .onChange(of: sourceCode) { _, _ in
                if speech.isListening { speech.stop() }
            }
            .onChange(of: targetCode) { _, _ in
                if !sourceText.isEmpty && autoTranslate { requestTranslation() }
            }
            .onDisappear {
                camera.stop()
                speech.stop()
                delayedTranslation?.cancel()
            }
            .translationTask(translationConfiguration) { session in
                let input = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !input.isEmpty else { return }
                let requestID = translationRequestID
                do {
                    let response = try await session.translate(input)
                    guard translationRequestID == requestID else { return }
                    let result = response.targetText
                    translatedText = result
                    screenServer.subtitle = result
                    isTranslating = false
                    errorMessage = nil
                    store.add(source: input, result: result, sourceLanguage: sourceCode,
                              targetLanguage: targetCode)
                } catch {
                    guard translationRequestID == requestID else { return }
                    isTranslating = false
                    errorMessage = "تعذرت الترجمة. تأكد من دعم اللغتين وتنزيل ملفات اللغة من iOS، ثم جرّب مجددًا. \(error.localizedDescription)"
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "captions.bubble.fill")
                .font(.title2.bold())
                .foregroundStyle(.black)
                .frame(width: 52, height: 52)
                .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("GAMECAPTION").font(.title2.bold()).tracking(1.2)
                Text("ترجمة الألعاب — بدون اشتراك")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("سجل الترجمات")
        }
        .foregroundStyle(.white)
        .padding(.top, 5)
    }

    private var modePicker: some View {
        HStack(spacing: 7) {
            ForEach(InputMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: option.symbol).font(.system(size: 18, weight: .semibold))
                        Text(option.rawValue).font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(mode == option ? Color.black : Color.white.opacity(0.77))
                    .background(mode == option ? Color.appAccent : .white.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 19))
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("مصدر الترجمة", icon: "viewfinder")
            switch mode {
            case .photo:
                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        actionLabel("الصور", icon: "photo", isPrimary: true)
                    }
                    Button { showingFileImporter = true } label: {
                        actionLabel("الملفات", icon: "folder", isPrimary: false)
                    }
                }
                if let photoPreview {
                    Image(uiImage: photoPreview)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("الصورة المحددة للترجمة")
                }
                if isReadingImage { ProgressView("جاري قراءة الصورة...").tint(Color.appAccent) }
            case .camera:
                if camera.isRunning {
                    CameraPreview(session: camera.session)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .bottom) {
                            Text("وجّه الكاميرا إلى نص اللعبة")
                                .font(.caption.bold()).padding(8)
                                .background(.black.opacity(0.7), in: Capsule())
                                .padding(10)
                        }
                }
                HStack {
                    Text("منطقة الفحص").font(.caption)
                    Slider(value: $scanCrop, in: 0.4...1.0, step: 0.1) { Text("منطقة الفحص") }
                        .tint(Color.appAccent)
                        .onChange(of: scanCrop) { _, value in camera.scanArea = value }
                }
                Button { camera.isRunning ? camera.stop() : camera.start() } label: {
                    actionLabel(camera.isRunning ? "إيقاف الكاميرا" : "بدء فحص الكاميرا",
                                icon: camera.isRunning ? "stop.fill" : "camera.fill", isPrimary: true)
                }
                Text(camera.statusText)
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            case .speech:
                Button { speech.isListening ? speech.stop() : speech.start(language: sourceCode) } label: {
                    actionLabel(speech.isListening ? "إيقاف الاستماع" : "ترجمة الكلام من الميكروفون",
                                icon: speech.isListening ? "stop.fill" : "mic.fill", isPrimary: true)
                }
                Text(speech.statusText).font(.caption).foregroundStyle(.white.opacity(0.65))
                Text("يستمع لميكروفون الآيفون فقط، وليس صوت Xbox الداخلي.")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            case .text:
                Text("اكتب النص مباشرة في المربع أدناه.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
            TextEditor(text: $sourceText)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 13))
                .overlay(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("النص الأصلي بيظهر هنا...")
                            .foregroundStyle(.white.opacity(0.34))
                            .padding(.leading, 16).padding(.top, 18)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("النص الأصلي")
            HStack {
                Button { sourceText = ""; translatedText = ""; screenServer.subtitle = "" } label: {
                    Label("مسح", systemImage: "trash")
                }
                .font(.caption)
                Spacer()
                Button { UIPasteboard.general.string = sourceText } label: {
                    Label("نسخ النص", systemImage: "doc.on.doc")
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.appAccent)
        }
        .captionCard()
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("اللغات", icon: "globe")
            HStack(spacing: 10) {
                languagePicker("من", selection: $sourceCode)
                Button {
                    let old = sourceCode
                    sourceCode = targetCode
                    targetCode = old
                    if !sourceText.isEmpty { requestTranslation() }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.headline).foregroundStyle(Color.appAccent)
                        .frame(width: 35, height: 45)
                }.accessibilityLabel("تبديل اللغات")
                languagePicker("إلى", selection: $targetCode)
            }
            Toggle("ترجمة تلقائية عند وصول نص جديد", isOn: $autoTranslate)
                .font(.subheadline).tint(Color.appAccent)
            Button { requestTranslation() } label: {
                HStack {
                    Spacer()
                    if isTranslating { ProgressView().tint(.black) }
                    Image(systemName: "character.bubble.fill")
                    Text(isTranslating ? "جاري الترجمة..." : "ترجم الآن")
                    Spacer()
                }
                .font(.headline)
                .padding(.vertical, 14)
                .foregroundStyle(.black)
                .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
        }
        .captionCard()
    }

    private func languagePicker(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.60))
            Picker(title, selection: selection) {
                ForEach(languages) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .tint(Color.appAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("الترجمة", icon: "captions.bubble")
            Text(translatedText.isEmpty ? "ستظهر الترجمة هنا بعد استخراج النص." : translatedText)
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 95, alignment: .topLeading)
                .foregroundStyle(translatedText.isEmpty ? .white.opacity(0.42) : .white)
                .textSelection(.enabled)
                .accessibilityLabel("الترجمة النهائية")
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.caption)
            }
            Divider().overlay(.white.opacity(0.12))
            HStack(spacing: 18) {
                Button {
                    UIPasteboard.general.string = translatedText
                } label: { Label("نسخ", systemImage: "doc.on.doc") }
                .disabled(translatedText.isEmpty)
                Button { speakTranslation() } label: {
                    Label("انطق", systemImage: "speaker.wave.2")
                }
                .disabled(translatedText.isEmpty)
                ShareLink(item: translatedText) {
                    Label("مشاركة", systemImage: "square.and.arrow.up")
                }
                .disabled(translatedText.isEmpty)
            }
            .font(.caption.bold())
            .foregroundStyle(Color.appAccent)
        }
        .captionCard()
    }

    private var toolsCard: some View {
        Button { showTV = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("شاشة ترجمة على الشبكة").font(.headline)
                    Text("افتح الترجمة على متصفح جهاز بنفس Wi-Fi")
                        .font(.caption).foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Image(systemName: "chevron.left").font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("الخصوصية والحدود", systemImage: "hand.raised")
                .font(.caption.bold())
            Text("ما فيه حساب أو اشتراك. الصور والكاميرا تعالج محليًا بتقنيات Apple. ترجمة النظام قد تحتاج تنزيل لغات. عرض النص في متصفح التلفزيون ليس طبقة فوق صورة Xbox أو PS، ولا يوجد التقاط لبث الألعاب من تطبيق آخر.")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 4)
    }

    private var historySheet: some View {
        NavigationStack {
            List {
                if store.items.isEmpty {
                    ContentUnavailableView("السجل فاضي", systemImage: "clock", description: Text("كل ترجمة ناجحة تنحفظ على الجهاز فقط."))
                } else {
                    ForEach(store.items) { item in
                        Button {
                            sourceText = item.source
                            translatedText = item.translation
                            sourceCode = item.from
                            targetCode = item.to
                            screenServer.subtitle = item.translation
                            showHistory = false
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(item.translation).font(.headline).foregroundStyle(.primary)
                                Text(item.source).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(item.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: store.remove)
                }
            }
            .navigationTitle("سجل الترجمات")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { showHistory = false } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }

    private var tvSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("عرض الترجمة على جهاز آخر", systemImage: "tv")
                        .font(.title3.bold())
                    Text("شغّل الخدمة، ثم افتح الرابط في متصفح جهاز متصل بنفس شبكة Wi-Fi. بيظهر نص الترجمة ويتحدث تلقائيًا. الخدمة تعمل والآيفون مفتوح والتطبيق في المقدمة فقط.")
                    Text("لا تدمج هذه الخدمة الترجمة فوق صورة اللعبة على مدخل HDMI؛ تحتاج الشاشة دعم صورة داخل صورة أو متصفح منفصل.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        if screenServer.running { screenServer.stop() }
                        else { screenServer.start() }
                    } label: {
                        Label(screenServer.running ? "إيقاف المشاركة" : "بدء المشاركة", systemImage: screenServer.running ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.appAccent)
                    if screenServer.running {
                        Text("الرابط:").font(.headline)
                        Text(screenServer.urlString).font(.callout.monospaced()).textSelection(.enabled)
                        Button { UIPasteboard.general.string = screenServer.urlString } label: {
                            Label("نسخ الرابط", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let message = screenServer.errorMessage {
                        Text(message).foregroundStyle(.orange)
                    }
                    Text("مهم: أي شخص يعرف الرابط داخل نفس الشبكة يقدر يشوف النص. أوقف المشاركة بعد الاستخدام.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("TV Link")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { showTV = false } } }
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(.white)
    }

    private func actionLabel(_ title: String, icon: String, isPrimary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(isPrimary ? .black : .white)
            .background(isPrimary ? Color.appAccent : .white.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 13))
    }

    @MainActor
    private func readPhoto(_ photo: PhotosPickerItem) async {
        isReadingImage = true
        errorMessage = nil
        defer { isReadingImage = false }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self) else {
                errorMessage = "ما قدرت أفتح الصورة."
                return
            }
            try await processImageData(data)
        } catch {
            errorMessage = "فشل استخراج النص: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func readImageFile(_ url: URL) async {
        isReadingImage = true
        errorMessage = nil
        defer { isReadingImage = false }
        let permitted = url.startAccessingSecurityScopedResource()
        defer { if permitted { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try await processImageData(data)
        } catch {
            errorMessage = "تعذرت قراءة الملف: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func processImageData(_ data: Data) async throws {
        photoPreview = UIImage(data: data)
        let recognized = try await OCRService.recognizeText(in: data)
        sourceText = recognized
        translatedText = ""
        if recognized.isEmpty { errorMessage = "ما لقينا نص واضح في الصورة." }
        else if autoTranslate { requestTranslation() }
    }

    private func updateFromLiveSource(_ newText: String) {
        guard newText != sourceText else { return }
        sourceText = newText
        guard autoTranslate else { return }
        delayedTranslation?.cancel()
        delayedTranslation = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            requestTranslation()
        }
    }

    private func requestTranslation() {
        let input = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { errorMessage = "أضف نص أولًا."; return }
        guard sourceCode != targetCode else {
            translatedText = input
            screenServer.subtitle = input
            isTranslating = false
            errorMessage = nil
            return
        }
        translationRequestID = UUID()
        isTranslating = true
        errorMessage = nil
        let source = Locale.Language(identifier: sourceCode)
        let target = Locale.Language(identifier: targetCode)
        if var configuration = translationConfiguration {
            configuration.source = source
            configuration.target = target
            configuration.invalidate()
            translationConfiguration = configuration
        } else {
            translationConfiguration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    private func speakTranslation() {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: translatedText)
        utterance.voice = AVSpeechSynthesisVoice(language: targetCode)
        utterance.rate = 0.48
        speaker.speak(utterance)
    }
}

private extension Color {
    static let appBackground = Color(red: 0.035, green: 0.058, blue: 0.11)
    static let appCard = Color(red: 0.082, green: 0.12, blue: 0.19)
    static let appAccent = Color(red: 0.38, green: 0.89, blue: 0.86)
}

private struct CaptionCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .foregroundStyle(.white)
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 19))
    }
}

private extension View {
    func captionCard() -> some View { modifier(CaptionCard()) }
}
