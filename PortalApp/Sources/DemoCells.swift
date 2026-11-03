import Foundation

/// DemoCells are the invented cells of the demo site and what each one holds, so a cell-scoped read answers with that cell's own rows.
enum DemoCells {
    struct Cell {
        let id: String
        let name: String
        let controllerIds: [String]
        let virtualControllerIds: [String]
        let cameraIds: [String]
        let ticketCount: Int
    }

    static let all: [Cell] = [
        Cell(id: "cell01", name: "Pick cell A", controllerIds: ["controller01", "controller03"], virtualControllerIds: ["virtual01"],
             cameraIds: ["camera01", "camera02", "camera03", "camera04"], ticketCount: 2),
        Cell(id: "cell02", name: "Packing line", controllerIds: ["controller02"], virtualControllerIds: [], cameraIds: [], ticketCount: 0),
        // A cell nothing is assigned to yet, for the empty state.
        Cell(id: "cell03", name: "Spare cell", controllerIds: [], virtualControllerIds: [], cameraIds: [], ticketCount: 0),
    ]

    static var rows: [[String: Any]] {
        all.map { ["id": $0.id, "name": $0.name, "controllerIds": $0.controllerIds, "virtualControllerIds": $0.virtualControllerIds, "cameraIds": $0.cameraIds] }
    }

    static func cell(_ variables: [String: Any]) -> Cell? {
        guard let cellId = variables["cellId"] as? String else { return nil }
        return all.first { $0.id == cellId } ?? Cell(id: cellId, name: cellId, controllerIds: [], virtualControllerIds: [], cameraIds: [], ticketCount: 0)
    }

    /// The rows of a per-controller answer that belong to the cell asked for, or all of them when no cell was asked for.
    static func narrow(_ rows: [[String: Any]], key: String = "controllerId", variables: [String: Any]) -> [[String: Any]] {
        guard let cell = cell(variables) else { return rows }
        return rows.filter { cell.controllerIds.contains($0[key] as? String ?? "") }
    }
}
