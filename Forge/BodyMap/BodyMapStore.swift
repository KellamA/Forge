import SwiftUI

/// One drawable piece of the body map.
struct BodyRegion {
    let slug: String
    let muscle: Muscle?
    let path: Path
}

/// One view (front or back) of one body model.
struct BodyFigure {
    let size: CGSize
    let outline: Path
    let regions: [BodyRegion]
}

/// Loads the body-map vector art (react-native-body-highlighter, MIT) from the bundle.
final class BodyMapStore: @unchecked Sendable {
    static let shared = BodyMapStore()

    private var figures: [String: BodyFigure] = [:]

    private struct FileRegion: Decodable {
        let slug: String
        let side: String
        let d: String
        let bbox: [Double]?
    }

    private struct FileFigure: Decodable {
        let width: Double
        let height: Double
        let outline: String
        let regions: [FileRegion]
    }

    private init() {
        guard let url = Bundle.main.url(forResource: "bodymap", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode([String: [String: FileFigure]].self, from: data) else {
            return
        }
        for (model, views) in file {
            for (side, fig) in views {
                let regions = fig.regions.map { r in
                    BodyRegion(slug: r.slug, muscle: Self.muscle(for: r), path: SVGPath.parse(r.d))
                }
                figures["\(model)-\(side)"] = BodyFigure(
                    size: CGSize(width: fig.width, height: fig.height),
                    outline: SVGPath.parse(fig.outline),
                    regions: regions
                )
            }
        }
    }

    func figure(_ model: BodyModel, _ side: BodySide) -> BodyFigure? {
        figures["\(model.rawValue)-\(side.rawValue)"]
    }

    private static func muscle(for region: FileRegion) -> Muscle? {
        switch region.slug {
        case "chest": return .chest
        case "deltoids": return .shoulders
        case "biceps": return .biceps
        case "triceps": return .triceps
        case "forearm": return .forearms
        case "abs", "obliques": return .abs
        case "trapezius": return .traps
        case "upper-back":
            // The source art draws the lats as the tall piece of "upper-back".
            if let b = region.bbox, b.count == 4, b[3] - b[1] > 140 { return .lats }
            return .upperBack
        case "lower-back": return .lowerBack
        case "gluteal": return .glutes
        case "quadriceps": return .quads
        case "hamstring": return .hamstrings
        case "adductors": return .adductors
        case "calves": return .calves
        case "neck": return .neck
        default: return nil
        }
    }
}

/// Parses the normalized path format produced by the build script (absolute M/L/C/Q/Z only).
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        let tokens = d.split(separator: " ")
        var i = 0
        func num() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        while i < tokens.count {
            let cmd = tokens[i]
            i += 1
            switch cmd {
            case "M":
                path.move(to: CGPoint(x: num(), y: num()))
            case "L":
                path.addLine(to: CGPoint(x: num(), y: num()))
            case "C":
                let c1 = CGPoint(x: num(), y: num())
                let c2 = CGPoint(x: num(), y: num())
                let p = CGPoint(x: num(), y: num())
                path.addCurve(to: p, control1: c1, control2: c2)
            case "Q":
                let c = CGPoint(x: num(), y: num())
                let p = CGPoint(x: num(), y: num())
                path.addQuadCurve(to: p, control: c)
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}
