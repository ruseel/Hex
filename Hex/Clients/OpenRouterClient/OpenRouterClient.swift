//
//  OpenRouterClient.swift
//  Hex
//
//  Created by Amp on 1/14/26.
//

import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let openRouterLogger = HexLog.transcription

@DependencyClient
public struct OpenRouterClient: Sendable {
  /// Process text through OpenRouter with the given prompt
  public var process: @Sendable (
    _ text: String,
    _ prompt: String,
    _ model: String,
    _ apiKey: String
  ) async throws -> String = { _, _, _, _ in "" }
  
  /// Check if OpenRouter is available with the given API key
  public var isAvailable: @Sendable (_ apiKey: String) async -> Bool = { _ in false }
}

extension OpenRouterClient: DependencyKey {
  public static let liveValue: OpenRouterClient = {
    let endpoint = "https://openrouter.ai/api/v1/chat/completions"
    
    return OpenRouterClient(
      process: { text, prompt, model, apiKey in
        let fullPrompt = prompt.replacingOccurrences(of: "{{text}}", with: text)
        
        guard let url = URL(string: endpoint) else {
          throw OpenRouterError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Hex Voice-to-Text", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
          "model": model,
          "messages": [
            ["role": "user", "content": fullPrompt]
          ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        openRouterLogger.info("Sending request to OpenRouter with model \(model)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
          throw OpenRouterError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
          if httpResponse.statusCode == 401 {
            throw OpenRouterError.unauthorized
          }
          openRouterLogger.error("OpenRouter returned status \(httpResponse.statusCode)")
          throw OpenRouterError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
          throw OpenRouterError.invalidResponseFormat
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
      },
      isAvailable: { apiKey in
        guard !apiKey.isEmpty else { return false }
        
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
          return false
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        
        do {
          let (_, response) = try await URLSession.shared.data(for: request)
          guard let httpResponse = response as? HTTPURLResponse else {
            return false
          }
          return httpResponse.statusCode == 200
        } catch {
          return false
        }
      }
    )
  }()
  
  public static let testValue = OpenRouterClient()
  
  public static let previewValue: OpenRouterClient = {
    OpenRouterClient(
      process: { text, _, _, _ in text },
      isAvailable: { _ in true }
    )
  }()
}

public enum OpenRouterError: LocalizedError {
  case invalidEndpoint
  case invalidResponse
  case httpError(Int)
  case invalidResponseFormat
  case unauthorized
  case connectionFailed
  
  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint:
      return "Invalid OpenRouter endpoint"
    case .invalidResponse:
      return "Invalid response from OpenRouter"
    case .httpError(let code):
      return "OpenRouter returned error code \(code)"
    case .invalidResponseFormat:
      return "Could not parse OpenRouter response"
    case .unauthorized:
      return "Invalid OpenRouter API key"
    case .connectionFailed:
      return "Could not connect to OpenRouter"
    }
  }
}

extension DependencyValues {
  public var openRouterClient: OpenRouterClient {
    get { self[OpenRouterClient.self] }
    set { self[OpenRouterClient.self] = newValue }
  }
}
