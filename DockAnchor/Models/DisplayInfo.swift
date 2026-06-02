
import Foundation
import CoreGraphics

extension DisplayInfo {
    func isEdgeBlocked(_ position: DockPosition, in displays: [DisplayInfo]) -> Bool {
        let others = displays.filter { $0.uuid != self.uuid }
        switch position {
        case .left:
            return others.contains { other in
                abs(other.frame.maxX - self.frame.minX) < 1 &&
                min(other.frame.maxY, self.frame.maxY) > max(other.frame.minY, self.frame.minY)
            }
        case .right:
            return others.contains { other in
                abs(other.frame.minX - self.frame.maxX) < 1 &&
                min(other.frame.maxY, self.frame.maxY) > max(other.frame.minY, self.frame.minY)
            }
        case .bottom:
            return others.contains { other in
                abs(other.frame.minY - self.frame.maxY) < 1 &&
                min(other.frame.maxX, self.frame.maxX) > max(other.frame.minX, self.frame.minX)
            }
        }
    }

    func hasAnyValidPosition(in displays: [DisplayInfo]) -> Bool {
        DockPosition.allCases.contains { !isEdgeBlocked($0, in: displays) }
    }
}

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let uuid: String
    let serialNumber: UInt32?
    let frame: CGRect
    let name: String
    let isPrimary: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
    }

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        return lhs.uuid == rhs.uuid &&
               lhs.frame.origin.x == rhs.frame.origin.x &&
               lhs.frame.origin.y == rhs.frame.origin.y &&
               lhs.frame.size.width == rhs.frame.size.width &&
               lhs.frame.size.height == rhs.frame.size.height
    }
}
