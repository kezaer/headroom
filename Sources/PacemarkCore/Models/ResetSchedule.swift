import Foundation

/// Why a provider window has no usable reset deadline. These categories are safe for
/// diagnostics and serialization; raw provider text stays outside the reason value.
public enum ResetUnresolvedReason: String, Sendable, Equatable, CaseIterable {
    case absent
    case elapsed
    case unparseable
    case implausible
    case invalidZone
    case legacyUnknown
}

/// Source-derived reset evidence. Only `.scheduled` carries a date, so an unknown
/// reset cannot accidentally become a fabricated deadline.
public enum ResetSchedule: Sendable, Equatable {
    case scheduled(Date)
    case unresolved(ResetUnresolvedReason)

    public var deadline: Date? {
        guard case .scheduled(let deadline) = self else { return nil }
        return deadline
    }

    public var unresolvedReason: ResetUnresolvedReason? {
        guard case .unresolved(let reason) = self else { return nil }
        return reason
    }
}

public enum ResetDiagnosticCategory: String, Sendable, Equatable, CaseIterable {
    case scheduled
    case absent
    case elapsed
    case unparseable
    case implausible
    case invalidZone = "invalid-zone"
    case legacyUnknown = "legacy-unknown"
}

/// Redaction-safe reset diagnostics. The API accepts only semantic evidence and an
/// observation timestamp, so provider labels, zones, paths, identity, and raw output
/// cannot cross the diagnostic boundary.
public enum ResetDiagnostic {
    public static func category(for schedule: ResetSchedule) -> ResetDiagnosticCategory {
        switch schedule {
        case .scheduled:
            .scheduled
        case .unresolved(let reason):
            switch reason {
            case .absent: .absent
            case .elapsed: .elapsed
            case .unparseable: .unparseable
            case .implausible: .implausible
            case .invalidZone: .invalidZone
            case .legacyUnknown: .legacyUnknown
            }
        }
    }

    public static func line(
        for schedule: ResetSchedule,
        observedAt: Date?,
        now: Date
    ) -> String {
        let age = observedAt.map { String(max(0, Int(now.timeIntervalSince($0)))) } ?? "unknown"
        return "reset-evidence=\(category(for: schedule).rawValue) age-seconds=\(age)"
    }
}

enum ResetSchedulePolicy {
    static func fallbackLifetime(for kind: WindowKind) -> TimeInterval {
        switch kind {
        case .fiveHour:
            return 5 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        case .billingPeriod(_, let duration):
            return duration.isFinite && duration > 0
                ? max(24 * 60 * 60, duration)
                : 24 * 60 * 60
        case .other(let label):
            return label.localizedCaseInsensitiveContains("weekly")
                ? 7 * 24 * 60 * 60
                : 24 * 60 * 60
        }
    }
}

enum LegacyResetClassifier {
    static func schedule(
        providerID: ProviderID,
        resetsAt: Date,
        capturedAt: Date?
    ) -> ResetSchedule {
        guard let capturedAt else { return .unresolved(.legacyUnknown) }
        if providerID == .claude,
           abs(resetsAt.timeIntervalSince(capturedAt)) < 1 {
            return .unresolved(.legacyUnknown)
        }
        return resetsAt > capturedAt
            ? .scheduled(resetsAt)
            : .unresolved(.elapsed)
    }
}

/// Interprets Claude's human-readable reset copy in the source-declared time zone.
/// Parsing is deterministic and bounded by the window's existing continuity horizon.
public enum ClaudeResetNormalizer {
    private static let immediateResetBoundary: TimeInterval = 60

    public static func schedule(
        label: String?,
        timeZoneIdentifier: String?,
        kind: WindowKind,
        now: Date,
        defaultTimeZone: TimeZone = .current,
        calendar suppliedCalendar: Calendar = Calendar(identifier: .gregorian),
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> ResetSchedule {
        guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unresolved(.absent)
        }

        let timeZone: TimeZone
        if let timeZoneIdentifier {
            guard let explicit = TimeZone(identifier: timeZoneIdentifier) else {
                return .unresolved(.invalidZone)
            }
            timeZone = explicit
        } else {
            timeZone = defaultTimeZone
        }

        var calendar = suppliedCalendar
        calendar.locale = locale
        calendar.timeZone = timeZone

        if let clock = clockComponents(in: label) {
            return normalizeClock(
                clock,
                kind: kind,
                now: now,
                calendar: calendar
            )
        }
        if let monthDay = monthDayComponents(in: label, locale: locale) {
            return normalizeMonthDay(
                monthDay,
                kind: kind,
                now: now,
                calendar: calendar
            )
        }
        return .unresolved(.unparseable)
    }

    private static func normalizeClock(
        _ clock: (hour: Int, minute: Int),
        kind: WindowKind,
        now: Date,
        calendar: Calendar
    ) -> ResetSchedule {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = clock.hour
        components.minute = clock.minute
        guard let sameDay = validatedDate(from: components, calendar: calendar) else {
            return .unresolved(.unparseable)
        }
        if sameDay.timeIntervalSince(now) >= -immediateResetBoundary {
            return plausible(sameDay, kind: kind, now: now)
        }

        // A clock-only label can legitimately refer to tomorrow. Accept that reading
        // only when it still fits the source window's maximum lifetime.
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: sameDay),
           nextDay.timeIntervalSince(now) <= ResetSchedulePolicy.fallbackLifetime(for: kind) {
            return .scheduled(nextDay)
        }
        return .unresolved(.elapsed)
    }

    private static func normalizeMonthDay(
        _ monthDay: (month: Int, day: Int, hour: Int, minute: Int),
        kind: WindowKind,
        now: Date,
        calendar: Calendar
    ) -> ResetSchedule {
        let captureYear = calendar.component(.year, from: now)
        let captureMonth = calendar.component(.month, from: now)
        var components = DateComponents(
            year: captureYear,
            month: monthDay.month,
            day: monthDay.day,
            hour: monthDay.hour,
            minute: monthDay.minute
        )
        guard let sameYear = validatedDate(from: components, calendar: calendar) else {
            return .unresolved(.unparseable)
        }
        if sameYear.timeIntervalSince(now) >= -immediateResetBoundary {
            return plausible(sameYear, kind: kind, now: now)
        }

        guard captureMonth == 12, monthDay.month == 1 else {
            return .unresolved(.elapsed)
        }
        components.year = captureYear + 1
        guard let nextYear = validatedDate(from: components, calendar: calendar) else {
            return .unresolved(.unparseable)
        }
        return plausible(nextYear, kind: kind, now: now)
    }

    private static func plausible(_ candidate: Date, kind: WindowKind, now: Date) -> ResetSchedule {
        let interval = candidate.timeIntervalSince(now)
        if interval < -immediateResetBoundary { return .unresolved(.elapsed) }
        if interval > ResetSchedulePolicy.fallbackLifetime(for: kind) {
            return .unresolved(.implausible)
        }
        return .scheduled(candidate)
    }

    private static func clockComponents(in label: String) -> (hour: Int, minute: Int)? {
        guard let match = label.firstMatch(
            of: /^Resets\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)$/.ignoresCase()
        ) else { return nil }
        return normalizedClock(hour: String(match.1), minute: match.2.map(String.init), meridiem: String(match.3))
    }

    private static func monthDayComponents(
        in label: String,
        locale: Locale
    ) -> (month: Int, day: Int, hour: Int, minute: Int)? {
        guard let match = label.firstMatch(
            of: /^Resets\s+([A-Za-z]+)\s+(\d{1,2})\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)$/.ignoresCase()
        ), let month = monthNumber(String(match.1), locale: locale), let day = Int(match.2),
              let clock = normalizedClock(
                hour: String(match.3),
                minute: match.4.map(String.init),
                meridiem: String(match.5)
              )
        else { return nil }
        return (month, day, clock.hour, clock.minute)
    }

    private static func normalizedClock(
        hour: String,
        minute: String?,
        meridiem: String
    ) -> (hour: Int, minute: Int)? {
        guard var hour = Int(hour), (1...12).contains(hour) else { return nil }
        let minute = minute.flatMap(Int.init) ?? 0
        guard (0...59).contains(minute) else { return nil }
        if meridiem.lowercased() == "pm", hour < 12 { hour += 12 }
        if meridiem.lowercased() == "am", hour == 12 { hour = 0 }
        return (hour, minute)
    }

    private static func monthNumber(_ name: String, locale: Locale) -> Int? {
        let normalized = name.lowercased()
        let formatter = DateFormatter()
        formatter.locale = locale
        let names = zip(formatter.monthSymbols, formatter.shortMonthSymbols)
        for (index, pair) in names.enumerated() {
            if normalized == pair.0.lowercased() || normalized == pair.1.lowercased() {
                return index + 1
            }
        }
        return nil
    }

    private static func validatedDate(from components: DateComponents, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: components) else { return nil }
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        let roundTrip = calendar.dateComponents(fields, from: date)
        for field in fields where components.value(for: field) != roundTrip.value(for: field) {
            return nil
        }
        return date
    }
}
