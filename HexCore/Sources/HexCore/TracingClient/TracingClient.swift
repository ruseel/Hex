//
//  TracingClient.swift
//  HexCore
//
//  Created by Amp on 1/14/26.
//

import Dependencies
import DependenciesMacros
import Foundation

/// Represents a trace context that can be passed between features.
/// Contains the trace ID and span ID needed to link child spans to parents.
public struct TraceContext: Equatable, Sendable, Codable {
  public let traceID: String
  public let spanID: String
  
  public init(traceID: String, spanID: String) {
    self.traceID = traceID
    self.spanID = spanID
  }
}

/// Represents an active span that can be ended when the operation completes.
public struct ActiveSpan: Sendable {
  public let name: String
  public let context: TraceContext
  let endAction: @Sendable () -> Void
  
  public init(name: String, context: TraceContext, endAction: @escaping @Sendable () -> Void) {
    self.name = name
    self.context = context
    self.endAction = endAction
  }
  
  public func end() {
    endAction()
  }
}

/// Span status for recording success or failure
public enum SpanStatus: Sendable {
  case ok
  case error(String)
}

/// Client for OpenTelemetry distributed tracing.
///
/// Provides spans for tracking transcription pipeline operations.
/// Traces can be exported to an OTLP-compatible collector (e.g., Jaeger, Zipkin).
///
/// ## Usage
///
/// ```swift
/// @Dependency(\.tracing) var tracing
///
/// // Start a root span
/// let span = await tracing.startSpan("transcription-pipeline", nil)
///
/// // Start a child span using parent context
/// let childSpan = await tracing.startSpan("recording", span.context)
/// // Do work...
/// await tracing.endSpan(childSpan, .ok)
///
/// await tracing.endSpan(span, .ok)
/// ```
@DependencyClient
public struct TracingClient: Sendable {
  /// Start a new span, optionally as a child of an existing span.
  ///
  /// - Parameters:
  ///   - name: The name of the span (e.g., "recording", "transcription")
  ///   - parentContext: The parent span's context, or nil for a root span
  /// - Returns: An ActiveSpan that must be ended when the operation completes
  public var startSpan: @Sendable (
    _ name: String,
    _ parentContext: TraceContext?
  ) async -> ActiveSpan = { name, _ in
    ActiveSpan(name: name, context: TraceContext(traceID: "", spanID: ""), endAction: {})
  }
  
  /// End a span with the given status.
  ///
  /// - Parameters:
  ///   - span: The span to end
  ///   - status: The status of the operation (ok or error)
  public var endSpan: @Sendable (
    _ span: ActiveSpan,
    _ status: SpanStatus
  ) async -> Void = { _, _ in }
  
  /// Add an attribute to an active span.
  ///
  /// - Parameters:
  ///   - span: The span to add the attribute to
  ///   - key: The attribute key
  ///   - value: The attribute value (string, int, double, or bool)
  public var setAttribute: @Sendable (
    _ span: ActiveSpan,
    _ key: String,
    _ value: String
  ) async -> Void = { _, _, _ in }
  
  /// Record an event (annotation) on a span.
  ///
  /// - Parameters:
  ///   - span: The span to record the event on
  ///   - name: The event name
  ///   - attributes: Optional attributes for the event
  public var recordEvent: @Sendable (
    _ span: ActiveSpan,
    _ name: String,
    _ attributes: [String: String]
  ) async -> Void = { _, _, _ in }
  
  /// End a span by its context.
  ///
  /// Use this when you only have the TraceContext (e.g., passed through state)
  /// and need to end the original span.
  ///
  /// - Parameters:
  ///   - context: The trace context of the span to end
  ///   - status: The status of the operation (ok or error)
  public var endSpanByContext: @Sendable (
    _ context: TraceContext,
    _ status: SpanStatus
  ) async -> Void = { _, _ in }
}

extension DependencyValues {
  /// Access the tracing client dependency.
  public var tracing: TracingClient {
    get { self[TracingClient.self] }
    set { self[TracingClient.self] = newValue }
  }
}
