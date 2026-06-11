import Foundation

enum BranchDateFormat: String, Codable, CaseIterable {
    case yyyymmdd
    case yyyymmddDashed
    case yyyymmddDotted
    case yyyymmddWithTail

    var displayName: String {
        switch self {
        case .yyyymmdd: return "YYYYMMDD"
        case .yyyymmddDashed: return "YYYY-MM-DD"
        case .yyyymmddDotted: return "YYYY.MM.DD"
        case .yyyymmddWithTail: return "YYYYMMDD-<尾缀>"
        }
    }

    var example: String {
        switch self {
        case .yyyymmdd: return "test-20260326"
        case .yyyymmddDashed: return "test-2026-03-26"
        case .yyyymmddDotted: return "test-2026.03.26"
        case .yyyymmddWithTail: return "test-20260326-hotfix"
        }
    }

    func regex(prefix: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: prefix)
        switch self {
        case .yyyymmdd:
            return "^\(escaped)-\\d{8}$"
        case .yyyymmddDashed:
            return "^\(escaped)-\\d{4}-\\d{2}-\\d{2}$"
        case .yyyymmddDotted:
            return "^\(escaped)-\\d{4}\\.\\d{2}\\.\\d{2}$"
        case .yyyymmddWithTail:
            return "^\(escaped)-\\d{8}-.+$"
        }
    }
}

enum BranchSelector: Equatable {
    case fixed(String)
    case rule(prefix: String, format: BranchDateFormat)
    case regex(String)

    var compiledRegex: String? {
        switch self {
        case .fixed: return nil
        case .rule(let prefix, let format): return format.regex(prefix: prefix)
        case .regex(let pattern): return pattern
        }
    }

    /// Best-effort literal prefix usable as the GitLab `search=^prefix-` filter.
    /// Only `.rule` exposes a known prefix; `.regex` returns nil because we cannot
    /// generally extract one without parsing.
    var searchPrefix: String? {
        if case .rule(let prefix, _) = self { return prefix }
        return nil
    }

    /// Display label for compact UI rendering when no resolved branch exists yet.
    var displayHint: String {
        switch self {
        case .fixed(let name): return name
        case .rule(let prefix, _): return "\(prefix)-…"
        case .regex(let pattern): return pattern
        }
    }
}

extension BranchSelector: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case prefix
        case format
    }

    private enum Kind: String, Codable {
        case fixed
        case rule
        case regex
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixed(let name):
            try c.encode(Kind.fixed, forKey: .type)
            try c.encode(name, forKey: .value)
        case .rule(let prefix, let format):
            try c.encode(Kind.rule, forKey: .type)
            try c.encode(prefix, forKey: .prefix)
            try c.encode(format, forKey: .format)
        case .regex(let pattern):
            try c.encode(Kind.regex, forKey: .type)
            try c.encode(pattern, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .fixed:
            self = .fixed(try c.decode(String.self, forKey: .value))
        case .rule:
            let prefix = try c.decode(String.self, forKey: .prefix)
            let format = try c.decode(BranchDateFormat.self, forKey: .format)
            self = .rule(prefix: prefix, format: format)
        case .regex:
            self = .regex(try c.decode(String.self, forKey: .value))
        }
    }
}
