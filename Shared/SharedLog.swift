//
//  SharedLog.swift
//  Groo
//
//  Central os.Logger instances for the app and AutoFill extension.
//  View in Console.app filtered by subsystem "dev.groo.ios".
//

import os

enum Log {
    static let subsystem = "dev.groo.ios"

    static let pass = Logger(subsystem: subsystem, category: "pass")
    static let autofill = Logger(subsystem: subsystem, category: "autofill")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let crypto = Logger(subsystem: subsystem, category: "crypto")
    static let wallet = Logger(subsystem: subsystem, category: "wallet")
    static let stocks = Logger(subsystem: subsystem, category: "stocks")
    static let push = Logger(subsystem: subsystem, category: "push")
    static let pad = Logger(subsystem: subsystem, category: "pad")
    static let scratchpad = Logger(subsystem: subsystem, category: "scratchpad")
    static let azan = Logger(subsystem: subsystem, category: "azan")
    static let network = Logger(subsystem: subsystem, category: "network")
}
