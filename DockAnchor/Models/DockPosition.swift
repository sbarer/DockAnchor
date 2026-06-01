
import Foundation

enum DockPosition: String, CaseIterable, Codable {
    case left = "left"
    case bottom = "bottom"
    case right = "right"

    var label: String {
        switch self {
        case .left: return "Left"
        case .bottom: return "Bottom"
        case .right: return "Right"
        }
    }
}
