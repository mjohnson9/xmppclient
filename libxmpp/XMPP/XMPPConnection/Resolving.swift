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
        get {
            return "_xmpp-client._tcp." + self.domain
        }
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
        print("\(self.domain): Resolving SRV records")
        self.resolver = SRVResolver(srvName: self.srvName)
        self.resolver.delegate = self
        self.resolver.start()
        
        self.resolverTimer = Timer(timeInterval: 1.0, target: self, selector: #selector(self.resolverTimeout), userInfo: nil, repeats: false)
        let runLoop = RunLoop.current
        runLoop.add(self.resolverTimer, forMode: RunLoop.Mode.common)
        runLoop.run()
    }
    
    // MARK: Handle DNS results
    
    private func switchToFallbackDNS() {
        print("\(self.domain): Using fallback DNS")
        self.connectionAddresses = [(host: self.domain, port: UInt16(5222))]
        self.startConnectionAttempts()
    }
    
    private func handleSRVResults(results: [SRVRecord]!) {
        if(results == nil || results.count == 0) {
            self.switchToFallbackDNS()
            return
        }
        
        // Check for service not supported record
        if(results.count == 1) {
            let result = results[0]
            if(result.target == ".") {
                print("\(self.domain): Encountered SRV record with target of \".\". Service is unavailable for this domain.")
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
        
        if(error != nil) {
            print("\(self.domain): Failed to resolve \(self.srvName): \(String(describing: error))")
            self.switchToFallbackDNS()
            return
        }
        
        print("\(self.domain): Received SRV records: \(String(describing: self.resolver.results))")
        self.handleSRVResults(results: self.convertSRVRecords(results: self.resolver.results))
    }
    
    // MARK: Timeout functions
    
    @objc private func resolverTimeout(timer: Timer) {
        if(self.resolver.isFinished) {
            return
        }
        
        print("\(self.domain): Resolver timed out")
        
        self.resolver.stop()
        self.handleSRVResults(results: self.convertSRVRecords(results: self.resolver.results))
    }
    
    // MARK: Helper functions
    
    private func convertSRVRecords(results: [Any]!) -> [SRVRecord]? {
        if(results == nil || results.count == 0) {
            return nil
        }
        
        var converted: [SRVRecord] = []
        converted.reserveCapacity(results.count)
        
        for resultAny in results {
            let result = resultAny as! NSDictionary
            let record = SRVRecord(dict: result)
            converted.append(record)
        }
        
        SRVRecord.shuffle(records: &converted)
        
        return converted
    }
}
