import Foundation
import Vision
import AppKit

/// On-device OCR via Apple's Vision framework — the screenshot never leaves
/// this Mac. Returns recognized lines top-to-bottom.
enum OcrService {
    static func recognizeText(in image: NSImage) async -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false // tickers/prices, not prose
            let handler = VNImageRequestHandler(cgImage: cg)
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}
