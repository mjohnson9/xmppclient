//
//  Resolving.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import os.log

private struct AssociatedKeys {
    static var resolver: UInt8 = 0
    static var resolverTimer: UInt8 = 0
}

extension XMPPConnection: SRVResolverDelegate {
    // MARK: Variables

    private var srvName: String {
        return "_xmpp-client._tcp." + self.domain
    }

    private var resolver: SRVResolver! {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.resolver) as? SRVResolver else {
                return nil
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.resolver, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private var resolverTimer: Timer! {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.resolverTimer) as? Timer else {
                return nil
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.resolverTimer, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // MARK: Functions exposed to other modules

    internal func resolveSRV() {
        os_log(.debug, log: XMPPConnection.osLog, "%s: Resolving SRV records", self.domain)
        self.resolver = SRVResolver(srvName: self.srvName)
        self.resolver.delegate = self
        self.resolver.start()

        self.resolverTimer = Timer(timeInterval: 1.0, target: self, selector: #selector(self.resolverTimeout), userInfo: nil, repeats: false)
        RunLoop.current.add(self.resolverTimer, forMode: RunLoop.Mode.common)
    }

    // MARK: Handle DNS results

    private func switchToFallbackDNS() {
        os_log(.debug, log: XMPPConnection.osLog, "%s: Switching to fallback DNS", self.domain)
        self.connectionAddresses = [(host: self.domain, port: UInt16(5222))]
        self.startConnectionAttempts()
    }

    private func handleSRVResults(results: [SRVRecord]!) {
        if results == nil || results.count == 0 {
            self.switchToFallbackDNS()
            return
        }

        // Check for service not supported record
        if results.count == 1 {
            let result = results[0]
            if result.target == "." {
                os_log(.info, log: XMPPConnection.osLog, "%s: The only SRV record for this domain has a target of \"%{public}s\". Service is unavailable for this domain.", self.domain, result.target)
                self.dispatchCannotConnect(error: XMPPServiceNotSupportedError())
                return
            }
        }

        self.connectionAddresses = []
        self.connectionAddresses.reserveCapacity(results.count)
        for result in results {
            self.connectionAddresses.append((host: result.target, port: result.port))
        }

        self.startConnectionAttempts()
    }

    // MARK: SRVResolverDelegate functions

    public func srvResolver(_ resolver: SRVResolver!, didStopWithError error: Error!) {
        self.resolverTimer.invalidate()
        self.resolverTimer = nil

        if error != nil {
            if let errorCasted = error as NSError? {
                os_log(.info, log: XMPPConnection.osLog, "%s: Failed to resolve SRV records: %@", self.domain, errorCasted)
            } else {
                os_log(.info, log: XMPPConnection.osLog, "%s: Failed to resolve SRV records: (unknown error type)", self.domain)
            }
            self.switchToFallbackDNS()
            return
        }

        os_log(.debug, log: XMPPConnection.osLog, "%s: Received SRV records: %@", self.domain, self.resolver.results)
        self.handleSRVResults(results: self.convertSRVRecords(results: self.resolver.results))
    }

    // MARK: Timeout functions

    @objc private func resolverTimeout(timer: Timer) {
        if self.resolver.isFinished {
            return
        }

        os_log(.info, log: XMPPConnection.osLog, "%s: Resolver timed out", self.domain)

        self.resolver.stop()
        self.handleSRVResults(results: self.convertSRVRecords(results: self.resolver.results))
    }

    // MARK: Helper functions

    private func convertSRVRecords(results: [Any]!) -> [SRVRecord]? {
        if results == nil || results.count == 0 {
            return nil
        }

        var converted: [SRVRecord] = []
        converted.reserveCapacity(results.count)

        for resultAny in results {
            guard let result = resultAny as? NSDictionary else {
                os_log(.error, "%s: SRV result record was not an NSDictionary", self.domain)
                fatalError()
            }
            let record = SRVRecord(dict: result)
            converted.append(record)
        }

        SRVRecord.shuffle(records: &converted)

        return converted
    }
}
