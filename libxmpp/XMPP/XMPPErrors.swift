//
//  XMPPErrors.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/22/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

class XMPPErrorStanza: Error {
    var stanza: Element
    
    init(stanza: Element) {
        self.stanza = stanza
    }
}

class XMPPNoSuchDomainError: Error {
}

class XMPPServiceNotSupportedError: Error {
}

class XMPPUnableToConnectError: Error {
}

class XMPPCriticalSSLError: Error {
}

class XMPPIncompatibleError: Error {
}
