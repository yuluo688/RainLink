import Foundation
import Security

private let protocolVersion = 1
private let keyBytes = 32
private let requestLimit = 256
private let service = "dev.rainlink.rainlink.credentials"
private let account = "master-v1"

private struct Request: Decodable {
  let version: Int
  let createIfMissing: Bool
}

private struct Reply: Encodable {
  let version = protocolVersion
  let status: String
  let key: Data?
}

private func query() -> [String: Any] {
  return [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
  ]
}

private func failure(_ status: OSStatus) -> Reply {
  if status == errSecUserCanceled {
    return Reply(status: "cancelled", key: nil)
  }
  // Locked/denied/authentication errors must never look like a missing item.
  return Reply(status: "unavailable", key: nil)
}

private func readKey() -> (OSStatus, Data?) {
  var attributes = query()
  attributes[kSecReturnData as String] = true
  attributes[kSecMatchLimit as String] = kSecMatchLimitOne
  var item: CFTypeRef?
  let status = SecItemCopyMatching(attributes as CFDictionary, &item)
  return (status, item as? Data)
}

private func reply(for request: Request) -> Reply {
  let (status, stored) = readKey()
  if status == errSecSuccess {
    guard let key = stored, key.count == keyBytes else {
      return Reply(status: "unavailable", key: nil)
    }
    return Reply(status: "ok", key: key)
  }
  guard status == errSecItemNotFound else { return failure(status) }
  guard request.createIfMissing else { return Reply(status: "missing", key: nil) }

  var generated = Data(count: keyBytes)
  defer { generated.resetBytes(in: 0..<generated.count) }
  let randomStatus = generated.withUnsafeMutableBytes { buffer -> OSStatus in
    guard let address = buffer.baseAddress else { return errSecParam }
    return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
  }
  guard randomStatus == errSecSuccess else { return failure(randomStatus) }
  var attributes = query()
  attributes[kSecValueData as String] = generated
  attributes[kSecAttrLabel as String] = "RainLink 凭据加密密钥"
  let added = SecItemAdd(attributes as CFDictionary, nil)
  // Concurrent hosts may both observe absence. Never update or replace an item;
  // on a duplicate, read the winner's key instead of returning the discarded one.
  guard added == errSecSuccess || added == errSecDuplicateItem else { return failure(added) }
  let (readStatus, readback) = readKey()
  guard readStatus == errSecSuccess, let key = readback, key.count == keyBytes else {
    return failure(readStatus)
  }
  return Reply(status: "ok", key: key)
}

private func run() -> Reply {
  guard CommandLine.arguments.count == 1 else { return Reply(status: "invalid_request", key: nil) }
  do {
    var input = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount: requestLimit - input.count + 1),
      !chunk.isEmpty
    {
      input.append(chunk)
      guard input.count <= requestLimit else { return Reply(status: "invalid_request", key: nil) }
    }
    guard let object = try JSONSerialization.jsonObject(with: input) as? [String: Any],
      Set(object.keys) == Set(["version", "createIfMissing"])
    else { return Reply(status: "invalid_request", key: nil) }
    let request = try JSONDecoder().decode(Request.self, from: input)
    guard request.version == protocolVersion else { return Reply(status: "invalid_request", key: nil) }
    return reply(for: request)
  } catch {
    return Reply(status: "invalid_request", key: nil)
  }
}

// This executable has no command-line options and emits one bounded JSON reply.
// stdout belongs to the host's private pipe; never run it through a public log.
private let response = run()
do {
  var output = try JSONEncoder().encode(response)
  defer { output.resetBytes(in: 0..<output.count) }
  try FileHandle.standardOutput.write(contentsOf: output)
} catch {
  exit(1)
}
