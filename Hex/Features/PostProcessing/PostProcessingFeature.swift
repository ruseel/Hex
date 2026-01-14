//
//  PostProcessingFeature.swift
//  Hex
//
//  Created by Amp on 1/14/26.
//

import ComposableArchitecture
import Foundation
import HexCore

private let postProcessingLogger = HexLog.transcription

/// Context passed from TranscriptionFeature when raw transcription completes
public struct TranscriptionContext: Equatable, Sendable {
  public let rawText: String
  public let audioURL: URL
  public let duration: TimeInterval
  public let sourceAppBundleID: String?
  public let sourceAppName: String?
  
  public init(
    rawText: String,
    audioURL: URL,
    duration: TimeInterval,
    sourceAppBundleID: String?,
    sourceAppName: String?
  ) {
    self.rawText = rawText
    self.audioURL = audioURL
    self.duration = duration
    self.sourceAppBundleID = sourceAppBundleID
    self.sourceAppName = sourceAppName
  }
}

@Reducer
struct PostProcessingFeature {
  @ObservableState
  struct State {
    var isProcessing: Bool = false
    var currentContext: TranscriptionContext?
    @Shared(.hexSettings) var hexSettings: HexSettings
    @Shared(.isRemappingScratchpadFocused) var isRemappingScratchpadFocused: Bool = false
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
  }

  enum Action {
    case processTranscription(TranscriptionContext)
    case postProcessingCompleted(String, TranscriptionContext)
    case postProcessingFailed(Error, TranscriptionContext)
    
    case delegate(Delegate)
    
    @CasePathable
    enum Delegate {
      case didFinishProcessing(String, TranscriptionContext)
      case didFailProcessing(Error, TranscriptionContext)
    }
  }

  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.soundEffects) var soundEffect
  @Dependency(\.transcriptPersistence) var transcriptPersistence
  @Dependency(\.ollamaClient) var ollamaClient
  @Dependency(\.openRouterClient) var openRouterClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .processTranscription(context):
        state.isProcessing = true
        state.currentContext = context
        
        let skipModifications = state.isRemappingScratchpadFocused
        let remappings = state.hexSettings.wordRemappings
        let removalsEnabled = state.hexSettings.wordRemovalsEnabled
        let removals = state.hexSettings.wordRemovals
        
        // Ollama settings
        let ollamaEnabled = state.hexSettings.ollamaPostProcessingEnabled
        let ollamaPrompt = state.hexSettings.ollamaActivePrompt ?? ""
        let ollamaModel = state.hexSettings.ollamaModel
        let ollamaEndpoint = state.hexSettings.ollamaEndpoint
        
        // OpenRouter settings
        let openRouterEnabled = state.hexSettings.openRouterPostProcessingEnabled
        let openRouterPrompt = state.hexSettings.openRouterActivePrompt ?? ""
        let openRouterModel = state.hexSettings.openRouterModel
        let openRouterApiKey = state.hexSettings.openRouterApiKey
        
        return .run { send in
          do {
            var output = context.rawText
            
            // Step 1: Apply word removals and remappings (unless scratchpad is focused)
            if !skipModifications {
              if removalsEnabled {
                let removedResult = WordRemovalApplier.apply(output, removals: removals)
                if removedResult != output {
                  let enabledRemovalCount = removals.filter(\.isEnabled).count
                  postProcessingLogger.info("Applied \(enabledRemovalCount) word removal(s)")
                }
                output = removedResult
              }
              
              let remappedResult = WordRemappingApplier.apply(output, remappings: remappings)
              if remappedResult != output {
                postProcessingLogger.info("Applied \(remappings.count) word remapping(s)")
              }
              output = remappedResult
            } else {
              postProcessingLogger.info("Scratchpad focused; skipping word modifications")
            }
            
            // Step 2: Apply LLM post-processing if enabled (OpenRouter takes precedence)
            if openRouterEnabled && !openRouterApiKey.isEmpty && !openRouterPrompt.isEmpty && !output.isEmpty {
              postProcessingLogger.info("Sending to OpenRouter for post-processing...")
              let result = try await openRouterClient.process(
                output,
                openRouterPrompt,
                openRouterModel,
                openRouterApiKey
              )
              if !result.isEmpty {
                postProcessingLogger.info("OpenRouter post-processing completed")
                output = result
              }
            } else if ollamaEnabled && !ollamaPrompt.isEmpty && !output.isEmpty {
              postProcessingLogger.info("Sending to Ollama for post-processing...")
              let ollamaResult = try await ollamaClient.process(
                output,
                ollamaPrompt,
                ollamaModel,
                ollamaEndpoint
              )
              if !ollamaResult.isEmpty {
                postProcessingLogger.info("Ollama post-processing completed")
                output = ollamaResult
              }
            }
            
            await send(.postProcessingCompleted(output, context))
          } catch {
            postProcessingLogger.error("Post-processing failed: \(error.localizedDescription)")
            await send(.postProcessingFailed(error, context))
          }
        }
        
      case let .postProcessingCompleted(processedText, context):
        state.isProcessing = false
        state.currentContext = nil
        
        guard !processedText.isEmpty else {
          return .send(.delegate(.didFinishProcessing(processedText, context)))
        }
        
        let transcriptionHistory = state.$transcriptionHistory
        let hexSettings = Shared(.hexSettings)
        
        return .run { send in
          do {
            try await finalizeAndPaste(
              result: processedText,
              context: context,
              transcriptionHistory: transcriptionHistory,
              hexSettings: hexSettings
            )
            await send(.delegate(.didFinishProcessing(processedText, context)))
          } catch {
            await send(.postProcessingFailed(error, context))
          }
        }
        
      case let .postProcessingFailed(error, context):
        state.isProcessing = false
        state.currentContext = nil
        
        // Clean up audio file on failure
        try? FileManager.default.removeItem(at: context.audioURL)
        
        return .send(.delegate(.didFailProcessing(error, context)))
        
      case .delegate:
        return .none
      }
    }
  }
  
  private func finalizeAndPaste(
    result: String,
    context: TranscriptionContext,
    transcriptionHistory: Shared<TranscriptionHistory>,
    hexSettings: Shared<HexSettings>
  ) async throws {
    if hexSettings.wrappedValue.saveTranscriptionHistory {
      let transcript = try await transcriptPersistence.save(
        result,
        context.audioURL,
        context.duration,
        context.sourceAppBundleID,
        context.sourceAppName
      )

      transcriptionHistory.withLock { history in
        history.history.insert(transcript, at: 0)

        if let maxEntries = hexSettings.wrappedValue.maxHistoryEntries, maxEntries > 0 {
          while history.history.count > maxEntries {
            if let removedTranscript = history.history.popLast() {
              Task {
                try? await transcriptPersistence.deleteAudio(removedTranscript)
              }
            }
          }
        }
      }
    } else {
      try? FileManager.default.removeItem(at: context.audioURL)
    }

    await pasteboard.paste(result)
    soundEffect.play(.pasteTranscript)
  }
}
