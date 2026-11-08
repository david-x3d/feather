//
//  ServerView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct ServerView: View {
	@StateObject private var _certificateServer = LocalCertificateServer()
	@State private var _showCertificateSetup = false
	
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	private let _serverMethods: [String] = [.localized("Fully Local"), .localized("Semi Local")]
	
	// MARK: Body
	var body: some View {
		Group {
			Section {
				Picker(
					.localized("Server Type"), 
					systemImage: "server.rack", 
					selection: $_serverMethod
				) {
					ForEach(_serverMethods.indices, id: \.description) { index in
						Text(_serverMethods[index]).tag(index)
					}
				}
				Toggle(
					.localized("Only use localhost address"), 
					systemImage: "lifepreserver", 
					isOn: $_ipFix
				)
				.disabled(_serverMethod != 1)
			}
			
			Section {
				Button(.localized("Install Local CA"), systemImage: "folder") {
					_showCertificateSetup = true
				}
				.disabled(_serverMethod != 0)
			} footer: {
				Text(.localized("Install the downloaded profile in Settings > General > VPN & Device Management. Then enable full trust for Feather Local Root CA in Settings > General > About > Certificate Trust Settings. This certificate is generated on your device and is used for Fully Local installation."))
			}
		}
		.alert(.localized("Local CA Setup"), isPresented: $_showCertificateSetup) {
			Button(.localized("Continue")) {
				_installCertificate()
			}
			Button(.localized("Cancel"), role: .cancel) {}
		} message: {
			Text(.localized("Allow the profile download, then open Settings > General > VPN & Device Management and install Feather Local Root CA. Next, open Settings > General > About > Certificate Trust Settings and enable full trust for Feather Local Root CA. Return to Feather and use Fully Local installation."))
		}
	}

	private func _installCertificate() {
		do {
			let url = try _certificateServer.start()
			UIApplication.shared.open(url) { success in
				if !success {
					_certificateServer.stop()
					UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Could not open Safari. Please try again."))
				}
			}
		} catch {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
		}
	}
}
