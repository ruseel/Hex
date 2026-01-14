//
//  TracingReducer.swift
//  Hex
//
//  Higher-order reducer that automatically instruments actions with OpenTelemetry spans.
//

import ComposableArchitecture
import HexCore

/// Protocol for feature states that carry a parent trace context.
/// Features implementing this protocol can use `.traced()` with automatic parent context.
public protocol TraceContextState {
  /// Long-lived context used as the parent for per-action spans.
  var traceContext: TraceContext? { get set }
}

/// Higher-order reducer that wraps another reducer to log action processing.
///
/// This is a lightweight alternative that:
/// 1. Logs action names via tracing for debugging/visibility
/// 2. Doesn't try to wrap effects (use `Effect.tracedRun` for that)
///
/// For full span lifecycle management around async effects, use `Effect.tracedRun` directly.
///
/// ## Usage
///
/// ```swift
/// @Reducer
/// struct MyFeature {
///   var body: some ReducerOf<Self> {
///     Reduce { state, action in
///       // reducer logic
///     }
///     .traced(
///       featureName: "MyFeature",
///       shouldTrace: { action in
///         switch action {
///         case .importantAction: return true
///         default: return false
///         }
///       }
///     )
///   }
/// }
/// ```
public struct TracingReducer<Base: Reducer>: Reducer {
  public typealias State = Base.State
  public typealias Action = Base.Action

  @Dependency(\.tracing) var tracing

  private let base: Base
  private let featureName: String
  private let shouldTrace: @Sendable (Action) -> Bool
  private let parentContext: @Sendable (State, Action) -> TraceContext?

  public init(
    base: Base,
    featureName: String? = nil,
    shouldTrace: @escaping @Sendable (Action) -> Bool = { _ in true },
    parentContext: @escaping @Sendable (State, Action) -> TraceContext? = { _, _ in nil }
  ) {
    self.base = base
    self.featureName = featureName ?? String(describing: Base.self)
    self.shouldTrace = shouldTrace
    self.parentContext = parentContext
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      guard shouldTrace(action) else {
        return base.reduce(into: &state, action: action)
      }

      let parent = parentContext(state, action)
      let spanName = makeSpanName(feature: featureName, action: action)

      let effect = base.reduce(into: &state, action: action)

      // For sync-only tracing: create a short-lived span to mark the action
      // This doesn't wrap the effect lifecycle - use Effect.tracedRun for that
      return .merge(
        .run { _ in
          let span = await tracing.startSpan(spanName, parent)
          await tracing.endSpan(span, .ok)
        },
        effect
      )
    }
  }
}

/// Derive span name from feature and action, e.g., "TranscriptionFeature.startRecording"
private func makeSpanName<Action>(feature: String, action: Action) -> String {
  let actionDescription = String(describing: action)
  // Extract the case name from the action description
  // e.g., "startRecording" from "startRecording(...)" or just "startRecording"
  let caseName: String
  if let firstParen = actionDescription.firstIndex(of: "(") {
    caseName = String(actionDescription[..<firstParen])
  } else {
    caseName = actionDescription
  }
  return "\(feature).\(caseName)"
}

// MARK: - Reducer Extensions

extension Reducer {
  /// Wrap this reducer with tracing instrumentation.
  ///
  /// This creates a short-lived span for each traced action to mark when it was processed.
  /// For async effect lifecycle tracing, use `Effect.tracedRun` directly in your effects.
  ///
  /// - Parameters:
  ///   - featureName: Name prefix for spans (defaults to type name)
  ///   - shouldTrace: Filter for which actions to trace
  ///   - parentContext: How to extract parent context from state
  /// - Returns: A traced reducer
  public func traced(
    featureName: String? = nil,
    shouldTrace: @escaping @Sendable (Action) -> Bool = { _ in true },
    parentContext: @escaping @Sendable (State, Action) -> TraceContext? = { _, _ in nil }
  ) -> some Reducer<State, Action> {
    TracingReducer(
      base: self,
      featureName: featureName,
      shouldTrace: shouldTrace,
      parentContext: parentContext
    )
  }
}

extension Reducer where State: TraceContextState {
  /// Wrap this reducer with tracing, automatically using `State.traceContext` as parent.
  ///
  /// - Parameters:
  ///   - featureName: Name prefix for spans (defaults to type name)
  ///   - shouldTrace: Filter for which actions to trace
  /// - Returns: A traced reducer
  public func traced(
    featureName: String? = nil,
    shouldTrace: @escaping @Sendable (Action) -> Bool = { _ in true }
  ) -> some Reducer<State, Action> {
    TracingReducer(
      base: self,
      featureName: featureName,
      shouldTrace: shouldTrace,
      parentContext: { state, _ in state.traceContext }
    )
  }
}
