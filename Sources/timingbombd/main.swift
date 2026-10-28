import Foundation
import TimingBombDaemon

let app = try await DaemonApp.bootstrap()
try await app.start()
