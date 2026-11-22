import SwiftUI
import PhotosUI
import Translation
import UniformTypeIdentifiers
import AVFoundation
import Combine

private enum InputMode: String, CaseIterable, Identifiable {
    case photo = "صورة"
    case camera = "كاميرا"
    case speech = "صوت"
    case screen = "شاشة"
    case text = "نص"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .photo: return "photo.on.rectangle"
        case .camera: return "camera.viewfinder"
        case .speech: return "waveform"
        case .screen: return "rectangle.on.rectangle"
        case .text: return "text.alignleft"
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    private struct TranslationRequest: Equatable {
        var id = UUID()
        var text: String
        var source: String
        var target: String
        var prepare = false
    }
    @StateObject private var store = CaptionStore()
    @StateObject private var camera = LiveCameraScanner()
    @StateObject private var speech = LiveSpeechRecognizer()
    @StateObject private var screenServer = LocalCaptionServer()
    @StateObject private var broadcastCapture = BroadcastCaptureStore()
    @StateObject private var neuralVoice = OfflineArabicVoice()
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
    @AppStorage("subtitleRegion.bottom") private var regionBottom = 0.0
    @AppStorage("subtitleRegion.height") private var regionHeight = 0.35
    @State private var displayedBroadcast: CaptureSnapshot?
    @State private var imageRequestID = UUID()
    @State private var errorMessage: String?
    @State private var offlineStatus: String?
    @State private var showHistory = false
    @State private var showTV = false
    @State private var translationRequest: TranslationRequest?
    @State private var delayedTranslation: Task<Void, Never>?
    @State private var photoPreview: UIImage?
    @State private var useNeuralArabicVoice = true
    @State private var voiceQuality: OfflineArabicVoice.Quality = .efficient
    @State private var speaker = AVSpeechSynthesizer()

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
            .onAppear { configureCapture() }
            .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
                if mode == .screen, scenePhase == .active { syncBroadcast() }
            }
            .onChange(of: selectedPhoto) { _, photo in
                guard let photo else { return }
                Task { await readPhoto(photo) }
            }
            .onChange(of: camera.recognizedText) { _, text in
                if mode == .camera { updateFromLiveSource(text) }
            }
            .onChange(of: camera.isRunning) { _, running in
                UIApplication.shared.isIdleTimerDisabled = running
            }
            .onChange(of: speech.transcript) { _, text in
                if mode == .speech, !text.isEmpty { updateFromLiveSource(text, debounce: true) }
            }
            .onChange(of: mode) { _, newMode in
                if newMode != .camera { camera.stop() }
                if newMode != .speech { speech.stop() }
                imageRequestID = UUID()
                isReadingImage = false
                displayedBroadcast = nil
                clearCaption()
                if newMode == .screen { syncBroadcast() }
            }
            .onChange(of: captureSettings) { old, new in
                if old.source != new.source { speech.stop() }
                configureCapture()
                if mode == .screen {
                    displayedBroadcast = nil
                    clearCaption()
                    syncBroadcast()
                } else if mode == .camera, old.region != new.region || old.source != new.source {
                    clearCaption()
                } else if old.source != new.source || old.target != new.target || old.translate != new.translate {
                    invalidateTranslation()
                    setCaption("")
                    if autoTranslate, !sourceText.isEmpty { requestTranslation() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    camera.stop()
                    speech.stop()
                    screenServer.stop()
                } else if phase == .active, mode == .screen {
                    syncBroadcast()
                }
            }
            .onDisappear {
                camera.stop()
                speech.stop()
                invalidateTranslation()
            }
            .translationTask(translationConfiguration) { session in
                await runTranslation(session)
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
                regionControls
                Button {
                    if camera.isRunning || camera.isStarting { camera.stop() }
                    else { camera.start() }
                } label: {
                    actionLabel(camera.isRunning || camera.isStarting ? "إيقاف الكاميرا" : "بدء فحص الكاميرا",
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
            case .screen:
                VStack(alignment: .leading, spacing: 10) {
                    Text("التقط النص من تطبيق Remote Play على الآيفون بعد بدء بث الشاشة بموافقتك.")
                        .font(.subheadline)
                    regionControls
                    ScreenBroadcastPicker()
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                    Text(broadcastCapture.settingsError ?? broadcastCapture.statusText)
                        .font(.caption).foregroundStyle(.white.opacity(0.76))
                    Text("الترجمة أثناء استخدام تطبيق آخر تتطلب iOS 26+، وتنزيل لغات Apple مسبقًا، وتوقيع App Groups للإضافة. بعض التطبيقات تحمي عرض الفيديو من الالتقاط.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    Text("لا يوفر هذا اتصال Xbox/PS مباشرًا ولا طبقة ترجمة فوق HDMI؛ بث الشاشة لا يبدأ تلقائيًا.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            case .text:
                Text("اكتب النص مباشرة في المربع أدناه.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
            TextEditor(text: Binding(get: { sourceText }, set: { value in
                invalidateTranslation()
                sourceText = value
                setCaption("")
            }))
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
                Button { clearCaption() } label: {
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
            if mode == .screen {
                Button("جهّز لغات الترجمة دون اتصال") { requestTranslation(prepare: true) }
                    .font(.caption.bold()).tint(Color.appAccent)
                    .disabled(isTranslating || sourceCode == targetCode)
                if let offlineStatus {
                    Text(offlineStatus).font(.caption).foregroundStyle(.white.opacity(0.75))
                }
            }
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
            if targetCode == "ar" {
                Toggle("نطق عربي عصبي محلي", isOn: $useNeuralArabicVoice)
                    .font(.caption).tint(Color.appAccent)
                if useNeuralArabicVoice {
                    Picker("جودة الصوت", selection: $voiceQuality) {
                        ForEach(OfflineArabicVoice.Quality.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(neuralVoice.status)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.60))
                }
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
            Text("ما فيه حساب أو اشتراك. الصور والكاميرا تعالج محليًا. بث شاشة التطبيقات الأخرى يحتاج إذن ReplayKit صريح، وقد تكون بعض الصور محمية من الالتقاط. لا توجد طبقة فوق HDMI أو اتصال Remote Play مباشر.")
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
                            invalidateTranslation()
                            sourceCode = item.from
                            targetCode = item.to
                            sourceText = item.source
                            setCaption(item.translation)
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

    private var captureSettings: CaptureSettings {
        CaptureSettings(source: sourceCode, target: targetCode, translate: autoTranslate,
                        region: SubtitleRegion(bottom: regionBottom, height: regionHeight))
    }

    private var regionControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("منطقة النص").font(.caption.bold())
            Slider(value: $regionHeight, in: 0.15...1, step: 0.05) { Text("ارتفاع المنطقة") }
                .onChange(of: regionHeight) { _, height in regionBottom = min(regionBottom, 1 - height) }
            Text("ارتفاع المنطقة: \(Int((regionHeight * 100).rounded()))٪")
            if regionHeight < 1 {
                Slider(value: $regionBottom, in: 0...(1 - regionHeight)) { Text("المسافة من أسفل الإطار") }
                Text("من أسفل الإطار: \(Int((regionBottom * 100).rounded()))٪")
            }
        }
        .font(.caption).tint(Color.appAccent)
    }

    private func configureCapture() {
        camera.configure(captureSettings)
        broadcastCapture.configure(captureSettings)
        offlineStatus = nil
    }

    private func syncBroadcast() {
        guard let snapshot = broadcastCapture.refresh(), snapshot.settings == captureSettings else {
            if displayedBroadcast != nil {
                displayedBroadcast = nil
                clearCaption()
            }
            return
        }
        guard snapshot.revision != displayedBroadcast?.revision ||
              snapshot.translation != displayedBroadcast?.translation else { return }
        displayedBroadcast = snapshot
        invalidateTranslation()
        sourceText = snapshot.source
        setCaption(snapshot.translation)
        if !snapshot.translation.isEmpty {
            store.add(source: snapshot.source, result: snapshot.translation,
                      sourceLanguage: snapshot.settings.source, targetLanguage: snapshot.settings.target)
        }
    }

    @MainActor
    private func readPhoto(_ photo: PhotosPickerItem) async {
        let language = sourceCode
        await importImage {
            guard let data = try await photo.loadTransferable(type: Data.self) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return try await OCRService.importImage(data: data, language: language)
        }
    }

    @MainActor
    private func readImageFile(_ url: URL) async {
        let language = sourceCode
        await importImage { try await OCRService.importImage(url: url, language: language) }
    }

    @MainActor
    private func importImage(_ read: () async throws -> OCRService.ImportedImage) async {
        guard mode == .photo else { return }
        let id = UUID()
        imageRequestID = id
        isReadingImage = true
        clearCaption()
        photoPreview = nil
        defer {
            if imageRequestID == id { isReadingImage = false }
        }
        do {
            let image = try await read()
            guard imageRequestID == id else { return }
            photoPreview = image.preview
            sourceText = image.text
            if image.text.isEmpty { errorMessage = "ما لقينا نص واضح في الصورة." }
            else if autoTranslate { requestTranslation() }
        } catch {
            guard imageRequestID == id else { return }
            errorMessage = "تعذرت قراءة الصورة: \(error.localizedDescription)"
        }
    }

    private func setCaption(_ text: String) {
        translatedText = text
        screenServer.subtitle = text
    }

    private func clearCaption() {
        invalidateTranslation()
        sourceText = ""
        setCaption("")
        errorMessage = nil
    }

    private func invalidateTranslation() {
        delayedTranslation?.cancel()
        translationRequest = nil
        isTranslating = false
    }

    private func updateFromLiveSource(_ newText: String, debounce: Bool = false) {
        guard newText != sourceText else { return }
        invalidateTranslation()
        sourceText = newText
        setCaption("")
        errorMessage = nil
        guard autoTranslate, !newText.isEmpty else { return }
        if debounce {
            delayedTranslation = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                requestTranslation()
            }
        } else {
            requestTranslation()
        }
    }

    private func requestTranslation(prepare: Bool = false) {
        invalidateTranslation()
        let input = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prepare || !input.isEmpty else { errorMessage = "أضف نص أولًا."; return }
        errorMessage = nil
        if sourceCode == targetCode {
            setCaption(input)
            return
        }
        translationRequest = TranslationRequest(text: input, source: sourceCode, target: targetCode, prepare: prepare)
        isTranslating = true
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

    @MainActor
    private func runTranslation(_ session: TranslationSession) async {
        guard let request = translationRequest else { return }
        defer {
            if translationRequest == request { isTranslating = false }
        }
        do {
            if request.prepare {
                try await session.prepareTranslation()
                guard translationRequest == request, !Task.isCancelled else { return }
                offlineStatus = "لغتا الترجمة جاهزتان للاستخدام دون اتصال."
            } else {
                let response = try await session.translate(request.text)
                guard translationRequest == request, !Task.isCancelled else { return }
                let result = response.targetText
                setCaption(result)
                store.add(source: request.text, result: result,
                          sourceLanguage: request.source, targetLanguage: request.target)
            }
        } catch {
            guard translationRequest == request, !Task.isCancelled else { return }
            if request.prepare { offlineStatus = nil }
            errorMessage = "تعذرت الترجمة. تحقق من توفر الزوج اللغوي وملفات اللغة في iOS. \(error.localizedDescription)"
        }
    }

    private func speakTranslation() {
        if targetCode == "ar" && useNeuralArabicVoice {
            neuralVoice.speak(translatedText, quality: voiceQuality)
            return
        }
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
