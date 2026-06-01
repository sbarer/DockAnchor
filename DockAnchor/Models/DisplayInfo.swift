
import Foundation
import CoreGraphics

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
