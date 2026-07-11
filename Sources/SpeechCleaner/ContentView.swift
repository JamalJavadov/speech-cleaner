import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.055, blue: 0.09), Color(red: 0.075, green: 0.055, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                Divider().overlay(Color.white.opacity(0.08))
                mainPanel
            }
        }
        .preferredColorScheme(.dark)
        .alert("Xəta", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Bağla", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Naməlum xəta")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech Cleaner").font(.title2.bold())
                    Text("Lokal nitq redaktoru").font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                label("TƏMİZLƏMƏ REJİMİ")
                Picker("Rejim", selection: $model.profile) {
                    ForEach(CleaningProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    label("UZUN PAUZA")
                    Spacer()
                    Text(String(format: "%.2f san", model.minimumLongPause)).monospacedDigit().foregroundStyle(.cyan)
                }
                Slider(value: $model.minimumLongPause, in: 0.35...1.5, step: 0.05)

                HStack {
                    label("SAXLANAN PAUZA")
                    Spacer()
                    Text(String(format: "%.2f san", model.keptPause)).monospacedDigit().foregroundStyle(.cyan)
                }
                Slider(value: $model.keptPause, in: 0.10...0.45, step: 0.01)
            }

            Toggle(isOn: $model.createMP4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Söz xəritəsi MP4")
                    Text("Waveform, söz və saniyə göstəricisi").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                label("NƏTİCƏ QOVLUĞU")
                Button(action: model.chooseOutputRoot) {
                    HStack {
                        Image(systemName: "folder")
                        Text(model.outputRoot.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .lineLimit(2)
                            .font(.caption)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle().fill(model.modelInstalled ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(model.modelInstalled ? "Azərbaycan modeli hazırdır" : "Model quraşdırılır")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(26)
        .frame(width: 310)
        .background(.black.opacity(0.18))
        .disabled(model.isProcessing)
    }

    private var mainPanel: some View {
        VStack(spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Səsi avtomatik təmizlə")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Uzun pauzaları qısalt, fon səsini azalt və Azərbaycan dilində söz xəritəsi yarat.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            inputCard

            if model.isProcessing || model.result != nil {
                progressCard
            } else {
                featureStrip
                Button(action: model.start) {
                    Label("Avtomatik emal et", systemImage: "wand.and.stars")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.inputURL == nil || !model.modelInstalled)
            }

            Spacer(minLength: 0)
        }
        .padding(32)
    }

    private var inputCard: some View {
        VStack(spacing: 18) {
            if let url = model.inputURL {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Color.cyan.opacity(0.12))
                        Image(systemName: "waveform").font(.system(size: 30)).foregroundStyle(.cyan)
                    }
                    .frame(width: 66, height: 66)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(url.lastPathComponent).font(.headline).lineLimit(1)
                        Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { model.playSource() } label: { Label("Dinlə", systemImage: "play.fill") }
                    Button("Dəyiş") { model.chooseInput() }
                }
            } else {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .top, endPoint: .bottom))
                VStack(spacing: 5) {
                    Text("Audio və ya video faylını bura atın").font(.title3.bold())
                    Text("WAV, MP3, M4A, AAC, MP4 və MOV").font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Fayl seç") { model.chooseInput() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 145)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(dropTargeted ? 0.10 : 0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(dropTargeted ? Color.cyan : Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: model.inputURL == nil ? [7] : [])))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in model.setInput(url) }
            }
            return true
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.status).font(.headline)
                    Text(model.isProcessing ? "Faylı bağlamayın; emal tamamilə lokal aparılır." : resultSummary)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.cyan)
            }

            ProgressView(value: model.progress).tint(.cyan)

            if model.isProcessing {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(model.activity.enumerated()), id: \.offset) { _, item in
                            Label(item, systemImage: item == model.activity.last ? "gearshape.2.fill" : "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(item == model.activity.last ? Color.cyan : Color.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                HStack {
                    Spacer()
                    Button("Dayandır", role: .destructive) { model.cancel() }
                }
            } else if let result = model.result {
                HStack(spacing: 12) {
                    resultMetric("Söz", "\(result.words.count)")
                    resultMetric("Əvvəl", duration(result.sourceDuration))
                    resultMetric("Sonra", duration(result.finalDuration))
                    resultMetric("Qənaət", duration(max(0, result.sourceDuration - result.finalDuration)))
                    Spacer()
                    Button { model.playCleaned() } label: { Label("Təmiz səsi dinlə", systemImage: "play.fill") }
                    if result.mapMP4 != nil {
                        Button { model.openMapVideo() } label: { Label("MP4 aç", systemImage: "film") }
                    }
                    Button { model.revealResults() } label: { Label("Nəticələr", systemImage: "folder") }
                        .buttonStyle(.borderedProminent)
                }
            }

        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.1)))
    }

    private var featureStrip: some View {
        HStack(spacing: 14) {
            feature("pause.circle", "Ağıllı pauza", "Sözlər qorunur")
            feature("waveform.badge.minus", "Fon təmizliyi", "Yüngül və təbii")
            feature("captions.bubble", "Azərbaycan dili", "Söz-saniyə xəritəsi")
            feature("lock.shield", "Tam lokal", "Fayl cihazdan çıxmır")
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(.cyan)
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.04)))
    }

    private func resultMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).monospacedDigit()
        }
    }

    private func label(_ value: String) -> some View {
        Text(value).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
    }

    private var resultSummary: String {
        guard let result = model.result else { return "" }
        return "\(result.words.count) söz xəritələndi • nəticələr \(result.outputDirectory.lastPathComponent) qovluğundadır"
    }

    private func duration(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
