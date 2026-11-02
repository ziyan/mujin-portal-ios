import PortalKit
import SwiftUI

/// VirtualControllerLive are the sections of a virtual controller's page below its status: its last 24 hours, active alarms and
/// tickets, and the way to subscribe to its alarms.
struct VirtualControllerLive: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let virtual: VirtualControllerSummary

    @State private var telemetry: SiteTelemetry?
    @State private var alarms: [SiteAlarm] = []
    @State private var tickets: [Ticket] = []

    var body: some View {
        Group {
            if let telemetry, telemetry.machinesTotal > 0 {
                Section("Last 24 hours") {
                    StatGrid {
                        StatTile(label: "Picked parts", value: telemetry.pickedParts.formatted(), detail: "\(telemetry.pickOperations) pick operations", symbol: "shippingbox")
                        StatTile(label: "Error rate", value: telemetry.errorRateText(), detail: "\(telemetry.interventions) of \(telemetry.pickedParts) picks needed a person", symbol: "exclamationmark.arrow.triangle.2.circlepath")
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            if !alarms.isEmpty {
                Section("Active alarms") { ForEach(alarms) { SiteRows.alarm($0) } }
            }
            if !tickets.isEmpty {
                Section("Tickets") {
                    ForEach(tickets.prefix(5)) { ticket in
                        NavigationLink(value: PortalRoute.ticket(id: ticket.id)) { TicketRow(ticket: ticket) }
                    }
                }
            }
            Section {
                NavigationLink(value: PortalRoute.virtualAlarmSubscriptions(virtual)) {
                    Label("Alarm subscriptions", systemImage: "bell.badge").foregroundStyle(.primary)
                }
            }
            // The load hangs on the last section's one row, not on the group: a modifier on the group would draw an empty row in the list.
            .task(id: virtual.id) {
                let connection = appModel.connection(for: session.account)
                telemetry = try? await connection.siteTelemetry(controllerIds: [], virtualControllerIds: [virtual.id])
                alarms = (try? await connection.virtualControllerAlarms(id: virtual.id)) ?? []
                tickets = (try? await connection.tickets(virtualControllerId: virtual.id, first: 20)) ?? []
            }
        }
    }
}
