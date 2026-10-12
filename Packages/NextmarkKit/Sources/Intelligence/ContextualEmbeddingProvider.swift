//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import Foundation
import NaturalLanguage
import Model

/// Sentence vectors from `NLContextualEmbedding`, mean-pooled over its token vectors.
/// Works without Apple Intelligence (Docs/architecture.md §5.3). There is one model
/// per script (Latin, CJK…), so the model ID is part of every vector: an English
/// query is compared with English and French items, not with Japanese ones; full-text
/// search still covers those.
public actor ContextualEmbeddingProvider: EmbeddingProvider {
    /// Loaded models by identifier. Loading takes a moment, so models stay loaded.
    private var models: [String: NLContextualEmbedding] = [:]

    static let assetsTimeLimit: TimeInterval = 120

    public init() {}

    public func embed(_ text: String) async throws -> TextEmbedding {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.emptyText }
        let language = NLLanguageRecognizer.dominantLanguage(for: String(trimmed.prefix(1_000)))
        let model = try await loadedModel(for: language)
        // Our estimate counts more tokens than the model's tokenizer, so this fits.
        let input = TokenBudget.truncate(trimmed, to: model.maximumSequenceLength)
        let result = try model.embeddingResult(for: input, language: language)
        var pool = VectorPool()
        result.enumerateTokenVectors(in: input.startIndex..<input.endIndex) { vector, _ in
            pool.add(vector)
            return true
        }
        guard let vector = pool.unitMean else { throw EmbeddingError.emptyText }
        return TextEmbedding(modelID: Self.modelID(of: model), vector: vector)
    }

    public func isCurrent(_ modelID: String) async -> Bool {
        let parts = modelID.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2, let model = NLContextualEmbedding(modelIdentifier: parts[0]) else { return false }
        return Self.modelID(of: model) == modelID
    }

    /// Whether the model for a language is already on this device.
    public static func hasAssets(forLanguage code: String) -> Bool {
        NLContextualEmbedding(language: NLLanguage(rawValue: code))?.hasAvailableAssets ?? false
    }

    static func modelID(of model: NLContextualEmbedding) -> String {
        "\(model.modelIdentifier)#\(model.revision)"
    }

    private func loadedModel(for language: NLLanguage?) async throws -> NLContextualEmbedding {
        // English only when no language was detected: a language without a model is
        // skipped (full-text search still finds it), not embedded with the wrong one.
        let candidate = language.map { NLContextualEmbedding(language: $0) } ?? NLContextualEmbedding(language: .english)
        guard let candidate else { throw EmbeddingError.unsupportedLanguage }
        if let loaded = models[candidate.modelIdentifier] { return loaded }
        if !candidate.hasAvailableAssets {
            // A download on a slow network shouldn't hold up the queue: give up after a
            // while (it carries on in the background) and let the job retry later.
            nonisolated(unsafe) let model = candidate
            let available = (try? await withTimeLimit(Self.assetsTimeLimit) {
                // The completion arrives on a framework queue, hence @Sendable.
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    model.requestAssets { @Sendable result, _ in
                        continuation.resume(returning: result == .available)
                    }
                }
            }) ?? false
            guard available else { throw EmbeddingError.assetsUnavailable }
        }
        try candidate.load()
        models[candidate.modelIdentifier] = candidate
        return candidate
    }
}
