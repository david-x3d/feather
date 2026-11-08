//
//  ServerInstaller+SSL.swift
//  Feather
//
//  Created by samsam on 10/6/26.
//

import Foundation
import Crypto
import SwiftASN1
import X509

extension ServerInstaller {
	static let serverHostname = "feather.backloop.dev"
	static let localCertificateDirectory = URL.applicationSupportDirectory.appendingPathComponent("LocalCA", isDirectory: true)

	@discardableResult
	static func createServerCert() throws -> (crt: URL, pem: URL) {
		let certificateURL = localCertificateDirectory.appendingPathComponent("local-server.crt")
		let privateKeyURL = localCertificateDirectory.appendingPathComponent("local-server.pem")
		
		let root = try rootMaterial()
		let serverPrivateKey = X509.Certificate.PrivateKey(P256.Signing.PrivateKey())
		
		let name = try DistinguishedName {
			CommonName(Self.serverHostname)
		}

		let now = Date()

		let extensions = try X509.Certificate.Extensions {
			Critical(
				BasicConstraints.notCertificateAuthority
			)
			Critical(
				KeyUsage(digitalSignature: true)
			)
			try ExtendedKeyUsage([.serverAuth])
			SubjectAlternativeNames([
				.dnsName(Self.serverHostname),
				.ipAddress(ASN1OctetString(contentBytes: [127, 0, 0, 1])),
			])
			SubjectKeyIdentifier(hash: serverPrivateKey.publicKey)
			AuthorityKeyIdentifier(keyIdentifier: SubjectKeyIdentifier(hash: root.certificate.publicKey).keyIdentifier)
		}

		let serverCertificate = try X509.Certificate(
			version: .v3,
			serialNumber: X509.Certificate.SerialNumber(),
			publicKey: serverPrivateKey.publicKey,
			notValidBefore: now.addingTimeInterval(-300),
			notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 365),
			issuer: root.certificate.subject,
			subject: name,
			signatureAlgorithm: .ecdsaWithSHA256,
			extensions: extensions,
			issuerPrivateKey: root.privateKey
		)

		try Data(serverCertificate.serializeAsPEM().pemString.utf8).write(to: certificateURL, options: .atomic)
		try Data(serverPrivateKey.serializeAsPEM().pemString.utf8).write(to: privateKeyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
		
		return (certificateURL, privateKeyURL)
	}
	
	static func rootCertificateProfile() throws -> Data {
		let root = try rootMaterial()
		let certificate: [String: Any] = [
			"PayloadType": "com.apple.security.root",
			"PayloadVersion": 1,
			"PayloadIdentifier": "app.feather.local-ca.certificate",
			"PayloadUUID": UUID().uuidString,
			"PayloadDisplayName": "Feather Local Root CA",
			"PayloadContent": root.der,
		]
		let profile: [String: Any] = [
			"PayloadType": "Configuration",
			"PayloadVersion": 1,
			"PayloadIdentifier": "app.feather.local-ca",
			"PayloadUUID": UUID().uuidString,
			"PayloadDisplayName": "Feather Local Root CA",
			"PayloadContent": [certificate],
		]
		return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
	}

	private static func rootMaterial() throws -> RootMaterialModel {
		try FileManager.default.createDirectory(at: localCertificateDirectory, withIntermediateDirectories: true)
		let rootPrivateKey = try createRootKey()
		let certificateURL = localCertificateDirectory.appendingPathComponent("FeatherLocalCA.cer")
		
		if FileManager.default.fileExists(atPath: certificateURL.path) {
			let der = try Data(contentsOf: certificateURL)
			if let certificate = try? X509.Certificate(derEncoded: Array(der)),
				certificate.publicKey == rootPrivateKey.publicKey,
				certificate.notValidBefore <= Date(),
				certificate.notValidAfter > Date().addingTimeInterval(60 * 60 * 24 * 365) {
					return RootMaterialModel(privateKey: rootPrivateKey, certificate: certificate, der: der)
			}
		}
		
		let certificate = try createRootCA(key: rootPrivateKey)
		var serializer = DER.Serializer()
		try serializer.serialize(certificate)
		let der = Data(serializer.serializedBytes)
		try der.write(to: certificateURL, options: .atomic)
		return RootMaterialModel(privateKey: rootPrivateKey, certificate: certificate, der: der)
	}
	
	private static func createRootCA(key: X509.Certificate.PrivateKey) throws -> X509.Certificate {
		let name = try DistinguishedName {
			CommonName("Feather Local Root CA")
		}
		let now = Date()
		let extensions = try X509.Certificate.Extensions {
			Critical(
				BasicConstraints.isCertificateAuthority(maxPathLength: 0)
			)
			Critical(
				KeyUsage(keyCertSign: true)
			)
			SubjectKeyIdentifier(hash: key.publicKey)
		}
		
		return try X509.Certificate(
			version: .v3,
			serialNumber: X509.Certificate.SerialNumber(),
			publicKey: key.publicKey,
			notValidBefore: now.addingTimeInterval(-300),
			notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 365 * 10),
			issuer: name,
			subject: name,
			signatureAlgorithm: .ecdsaWithSHA256,
			extensions: extensions,
			issuerPrivateKey: key
		)
	}
	
	private static func createRootKey() throws -> X509.Certificate.PrivateKey {
		let keyURL = localCertificateDirectory.appendingPathComponent("root.key")
		if FileManager.default.fileExists(atPath: keyURL.path) {
			let key = try P256.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
			return X509.Certificate.PrivateKey(key)
		}
		let key = P256.Signing.PrivateKey()
		try key.rawRepresentation.write(to: keyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
		return X509.Certificate.PrivateKey(key)
	}
}
