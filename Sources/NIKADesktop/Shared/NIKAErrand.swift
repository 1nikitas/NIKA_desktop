import Foundation

public enum NIKAErrandField: String, Codable, Equatable, Sendable {
  case instruction
  case cadence
  case localTime = "local_time"
  case weekday
  case creationSource = "creation_source"
  case timeZone = "timezone"
  case unknown

  init(serverValue: String) {
    self = Self(rawValue: serverValue) ?? .unknown
  }
}

public struct NIKAErrandValidationError: Error, Equatable, Sendable {
  public let field: NIKAErrandField
  public let message: String

  public init(field: NIKAErrandField, message: String) {
    self.field = field
    self.message = message
  }

  init?(serverMessage: String) {
    struct Detail: Decodable {
      let code: String
      let field: String
      let message: String
    }

    guard
      let data = serverMessage.data(using: .utf8),
      let detail = try? JSONDecoder().decode(Detail.self, from: data),
      detail.code == "invalid_schedule"
    else { return nil }

    self.init(
      field: NIKAErrandField(serverValue: detail.field),
      message: detail.message
    )
  }
}

public struct NIKAErrandLocalTime: Codable, Equatable, Hashable, Sendable {
  public let hour: Int
  public let minute: Int

  public init(hour: Int, minute: Int) throws {
    guard (0...23).contains(hour), (0...59).contains(minute) else {
      throw NIKAErrandValidationError(
        field: .localTime,
        message: "Local time must use a valid 24-hour hour and minute."
      )
    }
    self.hour = hour
    self.minute = minute
  }

  public var wireValue: String {
    String(format: "%02d:%02d", hour, minute)
  }
}

public enum NIKAErrandCadence: Codable, Equatable, Hashable, Sendable {
  case daily
  case weekdays
  /// ISO weekday: Monday = 0 through Sunday = 6, matching client-api.
  case weekly(weekday: Int)

  private enum Kind: String, Codable {
    case daily
    case weekdays
    case weekly
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case weekday
  }

  public var wireValue: String {
    switch self {
    case .daily: return "daily"
    case .weekdays: return "weekdays"
    case .weekly: return "weekly"
    }
  }

  public var weekday: Int? {
    guard case .weekly(let weekday) = self else { return nil }
    return weekday
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .daily:
      self = .daily
    case .weekdays:
      self = .weekdays
    case .weekly:
      let weekday = try container.decode(Int.self, forKey: .weekday)
      guard (0...6).contains(weekday) else {
        throw DecodingError.dataCorruptedError(
          forKey: .weekday,
          in: container,
          debugDescription: "Weekly weekday must be between 0 and 6."
        )
      }
      self = .weekly(weekday: weekday)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .daily:
      try container.encode(Kind.daily, forKey: .kind)
    case .weekdays:
      try container.encode(Kind.weekdays, forKey: .kind)
    case .weekly(let weekday):
      try container.encode(Kind.weekly, forKey: .kind)
      try container.encode(weekday, forKey: .weekday)
    }
  }
}

public enum NIKAErrandCreationSource: String, Codable, Equatable, Sendable {
  case chatOffer = "chat_offer"
  case managementEntry = "management_entry"
}

public struct NIKAErrandDraft: Codable, Equatable, Sendable {
  public var instruction: String
  public var cadence: NIKAErrandCadence
  public var localTime: NIKAErrandLocalTime
  public var creationSource: NIKAErrandCreationSource

  public init(
    instruction: String,
    cadence: NIKAErrandCadence,
    localTime: NIKAErrandLocalTime,
    creationSource: NIKAErrandCreationSource
  ) {
    self.instruction = instruction
    self.cadence = cadence
    self.localTime = localTime
    self.creationSource = creationSource
  }

  public func validated() throws -> NIKAErrandDraft {
    let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw NIKAErrandValidationError(
        field: .instruction,
        message: "An instruction is required."
      )
    }
    if case .weekly(let weekday) = cadence, !(0...6).contains(weekday) {
      throw NIKAErrandValidationError(
        field: .weekday,
        message: "Weekly cadence requires a weekday from 0 to 6."
      )
    }
    var copy = self
    copy.instruction = trimmed
    return copy
  }
}

public enum NIKAErrandKind: String, Codable, Equatable, Sendable {
  case task
  case reminder
  case oneTimeTask = "one_time_task"
}

public enum NIKAErrandRunState: String, Codable, CaseIterable, Equatable, Sendable {
  case neverRun = "never_run"
  case result
  case silent
  case failed
  case paused
}

public enum NIKAErrandFreshness: String, Codable, Equatable, Sendable {
  case live
  case cachedOffline
}

public enum NIKAErrandDomainError: Error, Equatable, Sendable {
  case unsupportedKind(String)
  case unsupportedSchedule
  case unsupportedRunState(String)
}

public struct NIKAErrand: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let chatID: String
  public let kind: NIKAErrandKind
  public let instruction: String
  public let cadence: NIKAErrandCadence
  public let localTime: NIKAErrandLocalTime
  public let timeZoneIdentifier: String
  public let nextFireAt: Date?
  public let lastFiredAt: Date?
  public let active: Bool
  public let fireCount: Int
  public let createdAt: Date?
  public let latestRunState: NIKAErrandRunState
  public let latestRunAt: Date?
  public let latestResult: String?
  public let latestError: String?
  public let creationSource: NIKAErrandCreationSource?

  public init(
    id: String,
    chatID: String,
    kind: NIKAErrandKind = .task,
    instruction: String,
    cadence: NIKAErrandCadence,
    localTime: NIKAErrandLocalTime,
    timeZoneIdentifier: String,
    nextFireAt: Date?,
    lastFiredAt: Date? = nil,
    active: Bool,
    fireCount: Int = 0,
    createdAt: Date? = nil,
    latestRunState: NIKAErrandRunState,
    latestRunAt: Date?,
    latestResult: String?,
    latestError: String?,
    creationSource: NIKAErrandCreationSource?
  ) {
    self.id = id
    self.chatID = chatID
    self.kind = kind
    self.instruction = instruction
    self.cadence = cadence
    self.localTime = localTime
    self.timeZoneIdentifier = timeZoneIdentifier
    self.nextFireAt = nextFireAt
    self.lastFiredAt = lastFiredAt
    self.active = active
    self.fireCount = fireCount
    self.createdAt = createdAt
    self.latestRunState = latestRunState
    self.latestRunAt = latestRunAt
    self.latestResult = latestResult
    self.latestError = latestError
    self.creationSource = creationSource
  }

  public init(schedule: BFFSchedule) throws {
    guard let kind = NIKAErrandKind(rawValue: schedule.kind) else {
      throw NIKAErrandDomainError.unsupportedKind(schedule.kind)
    }
    guard
      let cron = schedule.cronExpression,
      let recurrence = try Self.recurrence(from: cron)
    else {
      throw NIKAErrandDomainError.unsupportedSchedule
    }
    let runState: NIKAErrandRunState
    if !schedule.active {
      runState = .paused
    } else if let decoded = NIKAErrandRunState(rawValue: schedule.latestRunState) {
      runState = decoded
    } else {
      throw NIKAErrandDomainError.unsupportedRunState(schedule.latestRunState)
    }

    let source: NIKAErrandCreationSource?
    if case .string(let value) = schedule.metadata["creation_source"] {
      source = NIKAErrandCreationSource(rawValue: value)
    } else {
      source = nil
    }

    self.init(
      id: schedule.id,
      chatID: schedule.chatID,
      kind: kind,
      instruction: schedule.text,
      cadence: recurrence.cadence,
      localTime: recurrence.localTime,
      timeZoneIdentifier: schedule.timeZoneIdentifier,
      nextFireAt: Self.parseDate(schedule.nextFireAt),
      lastFiredAt: Self.parseDate(schedule.lastFiredAt),
      active: schedule.active,
      fireCount: schedule.fireCount,
      createdAt: Self.parseDate(schedule.createdAt),
      latestRunState: runState,
      latestRunAt: Self.parseDate(schedule.latestRunAt),
      latestResult: schedule.latestResult,
      latestError: schedule.latestError,
      creationSource: source
    )
  }

  private static func recurrence(
    from cron: String
  ) throws -> (cadence: NIKAErrandCadence, localTime: NIKAErrandLocalTime)? {
    let parts = cron.split(whereSeparator: \.isWhitespace).map(String.init)
    guard
      parts.count == 5,
      let minute = Int(parts[0]),
      let hour = Int(parts[1]),
      parts[2] == "*",
      parts[3] == "*"
    else { return nil }

    let time = try NIKAErrandLocalTime(hour: hour, minute: minute)
    switch parts[4] {
    case "*":
      return (.daily, time)
    case "1-5":
      return (.weekdays, time)
    default:
      guard let cronWeekday = Int(parts[4]), (0...6).contains(cronWeekday) else {
        return nil
      }
      return (.weekly(weekday: (cronWeekday + 6) % 7), time)
    }
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}
