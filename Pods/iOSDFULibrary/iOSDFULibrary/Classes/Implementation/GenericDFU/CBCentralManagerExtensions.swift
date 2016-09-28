//
//  CBCentralManagerExtensions.swift
//  Pods
//
//  Created by Hugues Bernet-Rollande on 27/9/16.
//
//

import CoreBluetooth

extension CBCentralManager {
    internal var centralManagerState: CBCentralManagerState  {
        get {
            return CBCentralManagerState(rawValue: state.rawValue) ?? .Unknown
        }
    }
}
