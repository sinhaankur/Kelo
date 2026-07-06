import Foundation

// MARK: - Profile
//
// The few facts about YOU that turn a generic savings rule into a number
// that's actually yours: age, gender, salary, country, and when you plan to
// retire. Kelo is for Ankur first — so the honest default is his real
// situation (Canada / CAD) — but every field is here so it generalises.
//
// Same on-device pattern as the rest ([[Spending.swift]]): a Codable struct
// behind a Store, gitignored, seeded from an example. Nothing here leaves the
// machine, and it only ever informs — it never acts ([[feedback_user_action_only]]).

public enum Gender: String, Codable, CaseIterable {
    case male, female, unspecified
}

/// Country drives the state-benefit assumption (how much retirement income you
/// DON'T have to self-fund) and the currency. Extend as needed; `.other` falls
/// back to fully self-funded, which is the conservative assumption.
public enum Country: String, Codable, CaseIterable {
    case canada, unitedStates, other

    public var label: String {
        switch self {
        case .canada: return "Canada"
        case .unitedStates: return "United States"
        case .other: return "Other"
        }
    }
}

public struct Profile: Codable {
    public var age: Int?
    public var gender: Gender
    /// Gross annual salary in the display currency. The savings multiples are
    /// meaningless without it.
    public var annualSalary: Double?
    public var country: Country
    /// Age you plan to retire (default 65 — Canada's common OAS anchor).
    public var retirementAge: Int
    /// Years you'll have CONTRIBUTED to the country's pension by retirement
    /// (CPP contributions / US work credits). Drives how much state benefit
    /// you actually earn — a short work-permit stint earns little.
    public var pensionContributionYears: Int?
    /// Years of RESIDENCY after 18 (Canada OAS needs 10 to collect anything,
    /// 40 for the full amount). For a few years on a permit this is small →
    /// little-to-no OAS. nil = assume same as contribution years.
    public var residencyYears: Int?

    public init(age: Int? = nil, gender: Gender = .unspecified,
                annualSalary: Double? = nil, country: Country = .canada,
                retirementAge: Int = 65,
                pensionContributionYears: Int? = nil,
                residencyYears: Int? = nil) {
        self.age = age
        self.gender = gender
        self.annualSalary = annualSalary
        self.country = country
        self.retirementAge = retirementAge
        self.pensionContributionYears = pensionContributionYears
        self.residencyYears = residencyYears
    }

    public var yearsToRetirement: Int? {
        guard let age else { return nil }
        return max(0, retirementAge - age)
    }
}

public enum ProfileStore {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("profile.json")
    }
    public static var exampleURL: URL {
        Portfolio.dirURL.appendingPathComponent("profile.example.json")
    }

    public static func load(from url: URL = fileURL) -> Profile {
        let fm = FileManager.default
        if url == fileURL, !fm.fileExists(atPath: url.path),
           fm.fileExists(atPath: exampleURL.path) {
            try? fm.copyItem(at: exampleURL, to: url)
        }
        guard let data = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(Profile.self, from: data)
        else { return Profile() }
        return p
    }

    public static func save(_ p: Profile, to url: URL = fileURL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let out = try? enc.encode(p) { try? out.write(to: url, options: .atomic) }
    }
}
