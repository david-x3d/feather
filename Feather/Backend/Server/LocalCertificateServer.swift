import Foundation
import Combine
import Vapor
import UIKit

final class LocalCertificateServer: ObservableObject {
	private var _server: Application?
	private var _shutdownTask: DispatchWorkItem?
	#if !targetEnvironment(macCatalyst)
	private var _backgroundTask: UIBackgroundTaskIdentifier = .invalid
	#endif

	deinit {
		stop()
	}

	func start() throws -> URL {
		stop()
		let profile = try ServerInstaller.rootCertificateProfile()
		let path = "\(UUID().uuidString).mobileconfig"
		let server = Application(ServerInstaller.env)
		server.http.server.configuration.address = .hostname("127.0.0.1", port: 0)
		server.get(.constant(path)) { _ in
			Response(status: .ok, headers: [
				"Content-Type": "application/x-apple-aspen-config",
				"Content-Disposition": "attachment; filename=FeatherLocalCA.mobileconfig",
				"Cache-Control": "no-store",
			], body: .init(data: profile))
		}

		do {
			try server.server.start()
			guard let port = server.http.server.shared.localAddress?.port,
				let url = URL(string: "http://127.0.0.1:\(port)/\(path)") else {
				throw CocoaError(.fileReadUnknown)
			}
			_server = server
			#if !targetEnvironment(macCatalyst)
			_backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Local CA download") { [weak self] in
				self?.stop()
			}
			#endif
			let task = DispatchWorkItem { [weak self] in
				self?.stop()
			}
			_shutdownTask = task
			DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: task)
			return url
		} catch {
			server.shutdown()
			throw error
		}
	}

	func stop() {
		_shutdownTask?.cancel()
		_shutdownTask = nil
		_server?.server.shutdown()
		_server?.shutdown()
		_server = nil
		#if !targetEnvironment(macCatalyst)
		if _backgroundTask != .invalid {
			UIApplication.shared.endBackgroundTask(_backgroundTask)
			_backgroundTask = .invalid
		}
		#endif
	}
}
