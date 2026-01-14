//
//  OllamaClient.swift
//  Hex
//
//  Created by Amp on 1/14/26.
//

import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let ollamaLogger = HexLog.transcription

@DependencyClient
public struct OllamaClient: Sendable {
  /// Process text through Ollama with the given prompt
  public var process: @Sendable (
    _ text: String,
    _ prompt: String,
    _ model: String,
    _ endpoint: String
  ) async throws -> String = { _, _, _, _ in "" }
  
  /// Check if Ollama is available at the given endpoint
  public var isAvailable: @Sendable (_ endpoint: String) async -> Bool = { _ in false }
}

extension OllamaClient: DependencyKey {
  public static let liveValue: OllamaClient = {
    OllamaClient(
      process: { text, prompt, model, endpoint in
        let fullPrompt = prompt.replacingOccurrences(of: "{{text}}", with: text)
        
        let url = URL(string: "\(endpoint)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
          "model": model,
          "prompt": fullPrompt,
          "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        ollamaLogger.info("Sending request to Ollama at \(endpoint) with model \(model)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
          throw OllamaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
          ollamaLogger.error("Ollama returned status \(httpResponse.statusCode)")
          throw OllamaError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
          throw OllamaError.invalidResponseFormat
        }
        
        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
      },
      isAvailable: { endpoint in
        guard let url = URL(string: "\(endpoint)/api/tags") else {
          return false
        }
        
        var request = URLRequest(url: url)
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
  
  public static let testValue = OllamaClient()
  
  public static let previewValue: OllamaClient = {
    OllamaClient(
      process: { text, _, _, _ in text },
      isAvailable: { _ in true }
    )
  }()
}

public enum OllamaError: LocalizedError {
  case invalidResponse
  case httpError(Int)
  case invalidResponseFormat
  case connectionFailed
  
  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid response from Ollama"
    case .httpError(let code):
      return "Ollama returned error code \(code)"
    case .invalidResponseFormat:
      return "Could not parse Ollama response"
    case .connectionFailed:
      return "Could not connect to Ollama"
    }
  }
}

extension DependencyValues {
  public var ollamaClient: OllamaClient {
    get { self[OllamaClient.self] }
    set { self[OllamaClient.self] = newValue }
  }
}
