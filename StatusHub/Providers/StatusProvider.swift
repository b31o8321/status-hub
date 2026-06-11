import Foundation

@MainActor
protocol StatusProvider: ObservableObject {
    var providerId: String { get }
    var providerTitle: String { get }
    var providerIcon: String { get }
    var overallStatus: HubStatus { get }

    func start()
    func refresh() async
}
