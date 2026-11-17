// Asks for Touch ID (or the login password) and exits 0 only on success.
// keychain_pinentry.py runs it before releasing a PIN, so signing needs the owner present.
// Build: swiftc -O -o ~/.muertos-gnupg/touchid-gate release/touchid_gate.swift
// Usage: touchid-gate "<reason shown in the prompt>"
import Foundation
import LocalAuthentication

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: touchid-gate <reason>\n".data(using: .utf8)!)
    exit(2)
}
let reason = CommandLine.arguments[1]
let context = LAContext()
var policyError: NSError?
guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
    FileHandle.standardError.write("touchid-gate: policy unavailable: \(policyError?.localizedDescription ?? "unknown")\n".data(using: .utf8)!)
    exit(1)
}
let done = DispatchSemaphore(value: 0)
var approved = false
var failure: Error?
context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
    approved = success
    failure = error
    done.signal()
}
done.wait()
if !approved {
    FileHandle.standardError.write("touchid-gate: denied: \(failure?.localizedDescription ?? "unknown")\n".data(using: .utf8)!)
    exit(1)
}
