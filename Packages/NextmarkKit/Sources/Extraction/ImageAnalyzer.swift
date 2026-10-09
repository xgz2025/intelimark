import Foundation

/// What Vision finds in an image: text, coarse labels and barcode payloads.
public struct ImageAnalysis: Sendable, Equatable {
    public var text: String?
    public var labels: [String]
    public var barcodes: [String]

    public init(text: String? = nil, labels: [String] = [], barcodes: [String] = []) {
        self.text = text
        self.labels = labels
        self.barcodes = barcodes
    }
}

public protocol ImageAnalyzing: Sendable {
    func analyze(imageAt url: URL) async throws -> ImageAnalysis
    func analyze(imageData data: Data) async throws -> ImageAnalysis
}

#if canImport(Vision)
import Vision

/// On-device OCR, classification and barcode detection (Docs/architecture.md §5.2).
/// Works on every device, with or without Apple Intelligence.
public struct VisionImageAnalyzer: ImageAnalyzing {
    static let minimumLabelConfidence: Float = 0.35
    static let maxLabels = 8

    public init() {}

    public func analyze(imageAt url: URL) async throws -> ImageAnalysis {
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let text = try await textRequest.perform(on: url)
        let labels = (try? await ClassifyImageRequest().perform(on: url)) ?? []
        let barcodes = (try? await DetectBarcodesRequest().perform(on: url)) ?? []
        return Self.analysis(text: text, labels: labels, barcodes: barcodes)
    }

    public func analyze(imageData data: Data) async throws -> ImageAnalysis {
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let text = try await textRequest.perform(on: data)
        let labels = (try? await ClassifyImageRequest().perform(on: data)) ?? []
        let barcodes = (try? await DetectBarcodesRequest().perform(on: data)) ?? []
        return Self.analysis(text: text, labels: labels, barcodes: barcodes)
    }

    static func analysis(
        text: [RecognizedTextObservation],
        labels: [ClassificationObservation],
        barcodes: [BarcodeObservation]
    ) -> ImageAnalysis {
        let lines = text.compactMap { $0.topCandidates(1).first?.string }
        let topLabels = labels
            .filter { $0.confidence >= minimumLabelConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxLabels)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        var payloads: [String] = []
        for payload in barcodes.compactMap(\.payloadString) where !payloads.contains(payload) {
            payloads.append(payload)
        }
        return ImageAnalysis(
            text: lines.isEmpty ? nil : lines.joined(separator: "\n"),
            labels: Array(topLabels),
            barcodes: payloads
        )
    }
}
#endif
