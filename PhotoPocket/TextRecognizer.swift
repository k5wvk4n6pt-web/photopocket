import Foundation
import Vision
import UIKit
import SwiftUI
import SwiftData

/// 写真の文字を読み取る（iPhoneに入っているAppleの文字認識を使用・通信なし）
enum TextRecognizer {
    static func recognize(data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let image = PhotoStorage.displayImage(data: data, maxPixel: 3000),
                  let cgImage = image.cgImage else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }

    /// 写真1枚を読み取って保存する
    @MainActor
    static func run(on item: PhotoItem, context: ModelContext) async {
        guard let data = await PhotoAssets.imageData(for: item) else { return }
        let text = (try? await recognize(data: data)) ?? ""
        item.recognizedText = text
        item.textRecognized = true
        try? context.save()
    }
}

/// 読み取った文字を表示・コピー・修正する画面
struct RecognizedTextSheet: View {
    let item: PhotoItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var working = false
    @State private var copied = false
    @State private var summarizing = false
    @State private var summary = ""
    @State private var summaryError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if Summarizer.isAvailable && !text.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("AIのまとめ", systemImage: "apple.intelligence")
                                .font(.subheadline.weight(.heavy))
                            Spacer()
                            Button {
                                Task { await makeSummary() }
                            } label: {
                                if summarizing { ProgressView() } else {
                                    Text(summary.isEmpty ? "要約する" : "作り直す").font(.subheadline.bold())
                                }
                            }
                            .disabled(summarizing)
                        }
                        if !summary.isEmpty {
                            Text(summary)
                                .font(.callout)
                                .textSelection(.enabled)
                        } else if let summaryError {
                            Text(summaryError).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Apple Intelligenceで、内容を短くまとめます（iPhoneの中だけで処理します）")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(corner: 16)
                }

                KeyInfoCard(text: text)

                if working {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("文字を読み取っています…").foregroundStyle(.secondary)
                    }
                } else if item.textRecognized && text.isEmpty {
                    Text("文字が見つかりませんでした。手書きや小さい文字は読み取りにくいことがあります。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(minHeight: 220)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: {
                        Label(copied ? "コピーしました" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BigButtonStyle())
                    .disabled(text.isEmpty)

                    Button {
                        Task { await read() }
                    } label: {
                        Label("読み直す", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(working)
                }

                Text("読み取った文字は「すべての写真」の検索で探せます。直接書き直すこともできます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("写真の文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        item.recognizedText = text
                        item.textRecognized = true
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .task {
                text = item.recognizedText
                summary = item.summary
                if !item.textRecognized { await read() }
            }
        }
    }

    private func makeSummary() async {
        summarizing = true
        summaryError = nil
        do {
            summary = try await Summarizer.summarize(text)
            item.summary = summary
            try? context.save()
        } catch {
            summaryError = "要約できませんでした。しばらくしてからもう一度お試しください。"
        }
        summarizing = false
    }

    private func read() async {
        working = true
        await TextRecognizer.run(on: item, context: context)
        text = item.recognizedText
        working = false
    }
}
