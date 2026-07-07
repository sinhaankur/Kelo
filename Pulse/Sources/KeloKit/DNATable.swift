import Foundation

// MARK: - Bundled SNP association table
//
// A small, curated set of well-established variant→trait associations drawn
// from the GWAS Catalog (open) and ClinVar (public domain). Each is a REAL,
// widely-cited association — chosen because it's robust, on a common array, and
// interpretable. This is deliberately conservative: better a short, honest list
// than a long list dressed up as fate. Every entry names its source; the app
// always frames these as statistical associations, never diagnoses.
//
// Extend this table (one line per marker) exactly like adding a body to the
// universe engine's astronomy table — the rest of Kelo needs no changes.

public enum DNATable {
    public static let associations: [SNPAssociation] = [
        // Caffeine metabolism — CYP1A2 (fast vs slow metabolizer).
        SNPAssociation(
            rsID: "rs762551", riskGenotype: "AA",
            trait: "Caffeine metabolism",
            note: "AA is the fast-metabolizer form — caffeine clears quicker; AC/CC clear it slower.",
            source: "GWAS Catalog", evidence: "well-established"),
        // Alcohol flush / metabolism — ALDH2.
        SNPAssociation(
            rsID: "rs671", riskGenotype: "AA",
            trait: "Alcohol metabolism",
            note: "The A allele reduces ALDH2 activity — slower acetaldehyde clearance, the 'flush' response.",
            source: "GWAS Catalog", evidence: "well-established"),
        // Lactase persistence — MCM6 upstream of LCT.
        SNPAssociation(
            rsID: "rs4988235", riskGenotype: "GG",
            trait: "Lactose tolerance",
            note: "GG is typically lactase non-persistent (adult lactose intolerance); A carriers usually digest dairy.",
            source: "GWAS Catalog", evidence: "well-established"),
        // Muscle performance — ACTN3 (the 'sprint' gene).
        SNPAssociation(
            rsID: "rs1815739", riskGenotype: "TT",
            trait: "Muscle fiber type",
            note: "TT (α-actinin-3 deficient) is more common in endurance athletes; C carriers skew toward power/sprint.",
            source: "GWAS Catalog", evidence: "reported"),
        // Vitamin D — GC binding protein.
        SNPAssociation(
            rsID: "rs2282679", riskGenotype: "GG",
            trait: "Vitamin D levels",
            note: "G allele is associated with lower circulating vitamin D — worth watching intake/sun.",
            source: "GWAS Catalog", evidence: "well-established"),
        // Caffeine consumption behaviour — AHR.
        SNPAssociation(
            rsID: "rs4410790", riskGenotype: "CC",
            trait: "Caffeine consumption",
            note: "C allele is associated with higher habitual caffeine intake.",
            source: "GWAS Catalog", evidence: "reported"),
        // Warfarin sensitivity — VKORC1 (clinically actionable).
        SNPAssociation(
            rsID: "rs9923231", riskGenotype: "TT",
            trait: "Warfarin sensitivity",
            note: "T allele lowers the warfarin dose needed — clinically relevant; a doctor uses this, not an app.",
            source: "ClinVar", evidence: "clinical"),
        // Hemochromatosis — HFE C282Y.
        SNPAssociation(
            rsID: "rs1800562", riskGenotype: "AA",
            trait: "Iron overload (hemochromatosis)",
            note: "AA is the C282Y homozygous form linked to hereditary hemochromatosis — discuss with a clinician.",
            source: "ClinVar", evidence: "clinical"),
        // Bitter taste — TAS2R38.
        SNPAssociation(
            rsID: "rs713598", riskGenotype: "GG",
            trait: "Bitter taste perception",
            note: "G allele tastes PTC/PROP bitterness strongly; C carriers are 'non-tasters'.",
            source: "GWAS Catalog", evidence: "well-established"),
        // Sleep / chronotype — near PER2/RGS16 region.
        SNPAssociation(
            rsID: "rs12946049", riskGenotype: "TT",
            trait: "Chronotype (morningness)",
            note: "Associated with morning-lark tendency — a nudge, not a verdict.",
            source: "GWAS Catalog", evidence: "reported"),
    ]
}
