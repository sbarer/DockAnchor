
import Foundation

struct DockProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var anchorDisplayUUID: String
    var createdAt: Date
    var autoActivate: Bool
    var dockPosition: DockPosition?
    var dockTileSize: Int?

    init(
        id: UUID = UUID(),
        name: String,
        anchorDisplayUUID: String,
        createdAt: Date = Date(),
        autoActivate: Bool = false,
        dockPosition: DockPosition? = nil,
        dockTileSize: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.anchorDisplayUUID = anchorDisplayUUID
        self.createdAt = createdAt
        self.autoActivate = autoActivate
        self.dockPosition = dockPosition
        self.dockTileSize = dockTileSize
    }

    // Custom decoder to handle migration from profiles without newer fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        anchorDisplayUUID = try container.decode(String.self, forKey: .anchorDisplayUUID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        autoActivate = try container.decodeIfPresent(Bool.self, forKey: .autoActivate) ?? false
        dockPosition = try container.decodeIfPresent(DockPosition.self, forKey: .dockPosition)
        dockTileSize = try container.decodeIfPresent(Int.self, forKey: .dockTileSize)
    }
}
