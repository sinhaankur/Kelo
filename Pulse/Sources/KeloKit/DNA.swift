import Foundation

// MARK: - DNA domain
//
// Kelo reads Ankur's real genotype (from a MyHeritage raw export) and maps it
// against PUBLIC, citable variant–trait associations — GWAS Catalog (open) and
// ClinVar (public domain). Never SNPedia (non-commercial license). This follows
// the universe engine's TRUTH pillar applied to the body: show REAL associations
// with their effect/evidence, LABEL them as statistical associations — never a
// diagnosis, never destiny.
//
// Privacy: the raw genome is huge and sensitive. Kelo keeps it on-device, the
// raw file gitignored (like the encrypted derived genome in the /dna work). The
// parser reads it; only the small set of matched, annotated markers is surfaced.
//
// File: MyHeritage raw export — tab-delimited, `#` comment lines, then
//   rsID \t chromosome \t position \t allele1 \t allele2
// (forward strand, GRCh37/38; indels use I/D).

/// One genotyped position from the raw file.
public struct Genotype: Equatable {
    public let rsID: String
    public let chromosome: String
    public let position: Int
    public let alleles: String      // normalized, e.g. "AG" (order-independent)

    public init(rsID: String, chromosome: String, position: Int, alleles: String) {
        self.rsID = rsID
        self.chromosome = chromosome
        self.position = position
        self.alleles = alleles
    }
}

/// A published variant→trait association from a public catalog. Bundled as a
/// small curated table so the app works offline; the raw genome is matched
/// against it locally (nothing is uploaded).
public struct SNPAssociation: Codable, Identifiable {
    public var id: String { rsID }
    public let rsID: String
    /// The genotype that carries the effect (e.g. "AA"), order-independent.
    public let riskGenotype: String
    public let trait: String            // e.g. "Caffeine metabolism"
    /// Plain, honest one-liner about what the association means.
    public let note: String
    /// Source catalog — "GWAS Catalog" or "ClinVar".
    public let source: String
    /// Loose strength label from the catalog ("well-established", "reported").
    public let evidence: String

    public init(rsID: String, riskGenotype: String, trait: String, note: String,
                source: String, evidence: String) {
        self.rsID = rsID
        self.riskGenotype = riskGenotype
        self.trait = trait
        self.note = note
        self.source = source
        self.evidence = evidence
    }
}

/// A match: one of the user's genotypes lines up with a known association.
public struct DNAInsight: Identifiable {
    public var id: String { association.rsID }
    public let association: SNPAssociation
    public let yourGenotype: String
    /// True when the user carries the association's flagged genotype.
    public let carriesTrait: Bool
}

public enum DNAParser {
    /// Parse a MyHeritage raw export into genotypes keyed by rsID. Skips `#`
    /// comment lines and any header row; tolerant of missing calls ("--").
    public static func parse(_ text: String) -> [String: Genotype] {
        var out: [String: Genotype] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            // MyHeritage uses tabs; some exports wrap fields in quotes.
            let cols = line.split(separator: "\t").map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            }
            guard cols.count >= 5 else { continue }
            let rsID = cols[0]
            guard rsID.hasPrefix("rs"), let pos = Int(cols[2]) else { continue }
            let a1 = cols[3].uppercased(), a2 = cols[4].uppercased()
            let alleles = normalizeAlleles(a1 + a2)
            out[rsID] = Genotype(rsID: rsID, chromosome: cols[1], position: pos, alleles: alleles)
        }
        return out
    }

    /// Order-independent genotype key ("GA" == "AG"), so matching is symmetric.
    public static func normalizeAlleles(_ s: String) -> String {
        String(s.uppercased().filter { "ACGTID".contains($0) }.sorted())
    }

    /// Match the parsed genome against the association table.
    public static func insights(genome: [String: Genotype],
                                table: [SNPAssociation]) -> [DNAInsight] {
        table.compactMap { assoc in
            guard let g = genome[assoc.rsID] else { return nil }
            let carries = g.alleles == normalizeAlleles(assoc.riskGenotype)
            return DNAInsight(association: assoc, yourGenotype: g.alleles, carriesTrait: carries)
        }
    }
}

public enum DNAStore {
    /// The raw genome lives here, gitignored — read once, kept on-device.
    public static var rawURL: URL {
        Portfolio.dirURL.appendingPathComponent("dna-raw.txt")
    }

    public static func loadGenome() -> [String: Genotype] {
        guard let text = try? String(contentsOf: rawURL, encoding: .utf8) else { return [:] }
        return DNAParser.parse(text)
    }

    public static var hasGenome: Bool {
        FileManager.default.fileExists(atPath: rawURL.path)
    }
}
