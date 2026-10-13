import Foundation

/// The JSON that crosses the `oai-events` data channel of a GPT-Live session,
/// in both directions — as values, without a socket in sight, so the whole
/// contract is testable from a string.
///
/// Reference: OpenAI Live API (`POST /v1/live/sessions`, WebRTC transport).
/// Only the events the app acts on are modelled; everything else is reported
/// as `.ignored(type:)` so an unknown event never becomes a crash or a silent
/// drop nobody can see in the log.

/// One fragment of speech on the session timeline. `startMs`/`endMs` are
/// milliseconds since the session began; intervals include the start and
/// exclude the end.
struct LiveVoiceTranscriptDelta: Equatable, Sendable {
  enum Speaker: String, Equatable, Sendable {
    case user
    case assistant
  }

  let speaker: Speaker
  let text: String
  let startMs: Int?
  let endMs: Int?
}

/// Server → client.
enum LiveVoiceServerEvent: Equatable, Sendable {
  case sessionStarted(sessionID: String?)
  case transcript(LiveVoiceTranscriptDelta)
  /// The live model wants the app to do the actual work for the current turn.
  /// Carries no text: what the user asked is reconstructed from the transcript.
  case delegationCreated(delegationID: String, target: String)
  /// Acknowledgement of one of the `*.append` commands.
  case appended(kind: String, clientEventID: String?)
  case inputMuted(Bool)
  case usageUpdated(seconds: Double, contextUsageRatio: Double?)
  case sessionClosed(reason: String?, seconds: Double?)
  case error(code: String?, message: String, clientEventID: String?)
  case ignored(type: String)

  /// `nil` only when the payload is not a JSON object with a `type`.
  static func parse(_ data: Data) -> LiveVoiceServerEvent? {
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = object["type"] as? String
    else { return nil }
    return parse(type: type, object: object)
  }

  static func parse(type: String, object: [String: Any]) -> LiveVoiceServerEvent {
    switch type {
    case "session.started":
      let session = object["session"] as? [String: Any]
      return .sessionStarted(sessionID: session?["id"] as? String)

    case "session.input_transcript.delta", "session.output_transcript.delta":
      let speaker: LiveVoiceTranscriptDelta.Speaker =
        type == "session.input_transcript.delta" ? .user : .assistant
      return .transcript(
        LiveVoiceTranscriptDelta(
          speaker: speaker,
          text: object["delta"] as? String ?? "",
          startMs: Self.int(object["start_ms"]),
          endMs: Self.int(object["end_ms"])
        )
      )

    case "session.delegation.created":
      let delegation = object["delegation"] as? [String: Any]
      let id = delegation?["id"] as? String ?? object["delegation_id"] as? String ?? ""
      let target = delegation?["target"] as? String ?? object["target"] as? String ?? "client"
      return .delegationCreated(delegationID: id, target: target)

    case "session.commentary.appended", "session.thinking.appended",
      "session.instructions.appended":
      return .appended(
        kind: String(type.dropFirst("session.".count).dropLast(".appended".count)),
        clientEventID: object["client_event_id"] as? String
      )

    case "session.input_audio.muted":
      return .inputMuted(true)
    case "session.input_audio.unmuted":
      return .inputMuted(false)

    case "session.usage.updated":
      let usage = object["usage"] as? [String: Any]
      let window = object["context_window"] as? [String: Any]
      return .usageUpdated(
        seconds: Self.double(usage?["seconds"]) ?? 0,
        contextUsageRatio: Self.double(window?["usage_ratio"])
      )

    case "session.closed":
      let usage = object["usage"] as? [String: Any]
      return .sessionClosed(
        reason: object["reason"] as? String,
        seconds: Self.double(usage?["seconds"])
      )

    case "error":
      let error = object["error"] as? [String: Any]
      let message = error?["message"] as? String
        ?? object["message"] as? String
        ?? L("Сервис голоса вернул ошибку.")
      return .error(
        code: error?["code"] as? String ?? object["code"] as? String,
        message: message,
        clientEventID: object["client_event_id"] as? String
      )

    default:
      return .ignored(type: type)
    }
  }

  private static func int(_ value: Any?) -> Int? {
    switch value {
    case let number as NSNumber: return number.intValue
    case let string as String: return Int(string)
    default: return nil
    }
  }

  private static func double(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber: return number.doubleValue
    case let string as String: return Double(string)
    default: return nil
    }
  }
}

/// Client → server.
enum LiveVoiceClientEvent: Equatable, Sendable {
  /// Something the model should say out loud (it paraphrases). Tied to the
  /// delegation it answers.
  case commentaryAppend(delegationID: String, content: String, eventID: String)
  /// Facts for the model to know, not to read out. `delegationID` may be nil
  /// for session-wide context.
  case thinkingAppend(delegationID: String?, content: String, eventID: String)
  case instructionsAppend(content: String, eventID: String)
  case muteInput(Bool)
  case close

  var type: String {
    switch self {
    case .commentaryAppend: "session.commentary.append"
    case .thinkingAppend: "session.thinking.append"
    case .instructionsAppend: "session.instructions.append"
    case .muteInput(let muted): muted ? "session.input_audio.mute" : "session.input_audio.unmute"
    case .close: "session.close"
    }
  }

  var object: [String: Any] {
    switch self {
    case .commentaryAppend(let delegationID, let content, let eventID):
      return [
        "type": type,
        "event_id": eventID,
        "delegation_id": delegationID,
        "content": content,
      ]
    case .thinkingAppend(let delegationID, let content, let eventID):
      var object: [String: Any] = [
        "type": type,
        "event_id": eventID,
        "content": content,
      ]
      // `null` is the documented spelling for "not about a delegation".
      object["delegation_id"] = delegationID ?? NSNull()
      return object
    case .instructionsAppend(let content, let eventID):
      return [
        "type": type,
        "event_id": eventID,
        "delegation_id": NSNull(),
        "content": content,
      ]
    case .muteInput, .close:
      return ["type": type]
    }
  }

  func encoded() throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }
}
