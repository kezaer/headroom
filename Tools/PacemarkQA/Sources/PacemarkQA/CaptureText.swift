import Foundation
import Vision

/// Word rectangles recover painted labels that AppKit merges into a single AX control.
func captureWords(at path: String, fastOnly: Bool = false) throws {
    let url = URL(fileURLWithPath: path)
    func recognize(_ level: VNRequestTextRecognitionLevel) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        if level == .fast { request.revision = 1 }
        try VNImageRequestHandler(url: url).perform([request])
        return request.results ?? []
    }
    // The accurate reader can reject valid screenshots on some macOS versions.
    let lines: [VNRecognizedTextObservation]
    if !fastOnly, let accurate = try? recognize(.accurate), !accurate.isEmpty {
        lines = accurate
    } else {
        lines = try recognize(.fast)
    }
    var words: [[String: Any]] = []
    for line in lines {
        guard let candidate = line.topCandidates(1).first else { continue }
        for word in candidate.string.split(whereSeparator: { $0.isWhitespace }) {
            guard let box = try candidate.boundingBox(for: word.startIndex..<word.endIndex)?.boundingBox else { continue }
            words.append(["text": String(word), "x": box.minX, "y": 1 - box.maxY, "w": box.width, "h": box.height])
        }
    }
    let data = try JSONSerialization.data(withJSONObject: words)
    print(String(decoding: data, as: UTF8.self))
}
