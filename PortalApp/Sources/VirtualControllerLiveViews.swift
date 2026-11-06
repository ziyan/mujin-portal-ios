import PortalKit
import SwiftUI

/// The sections of a virtual controller's page below its status: its last 24 hours, active alarms and tickets, and the way to
/// subscribe to its alarms. Built as part of the page's own list, because a list draws a custom view as one row.
extension VirtualControllerDetailView {
    @ViewBuilder
    var liveSections: some View {
        Group {
            if let telemetry = liveTelemetry, telemetry.machinesTotal > 0 {
                Section("Last 24 hours") {
                    StatGrid {
                        StatTile(label: "Picked parts", value: telemetry.pickedParts.formatted(), detail: "\(telemetry.pickOperations) pick operations", symbol: "shippingbox")
                        StatTile(label: "Error rate", value: telemetry.errorRateText(), detail: "\(telemetry.interventions) of \(telemetry.pickedParts) picks needed a person", symbol: "exclamationmark.arrow.triangle.2.circlepath")
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            if !liveAlarms.isEmpty {
                Section("Active alarms") { ActiveAlarmRows.rows(liveAlarms, controllers: []) }
            }
            if !liveTickets.isEmpty {
                Section("Tickets") {
                    ForEach(liveTickets.prefix(5)) { ticket in
                        NavigationLink(value: PortalRoute.ticket(id: ticket.id)) { TicketRow(ticket: ticket) }
                    }
                }
            }
            Section {
                NavigationLink(value: PortalRoute.virtualAlarmSubscriptions(virtual)) {
                    Label("Alarm subscriptions", systemImage: "bell.badge").foregroundStyle(.primary)
                }
            }
        }
    }

    func loadLive() async {
        let connection = appModel.connection(for: session.account)
        liveTelemetry = try? await connection.siteTelemetry(controllerIds: [], virtualControllerIds: [virtual.id])
        liveAlarms = (try? await connection.virtualControllerAlarms(id: virtual.id)) ?? []
        liveTickets = (try? await connection.tickets(virtualControllerId: virtual.id, first: 20)) ?? []
    }
}
