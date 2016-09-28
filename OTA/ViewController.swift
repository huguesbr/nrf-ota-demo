//
//  ViewController.swift
//  OTA
//
//  Created by Hugues Bernet-Rollande on 28/9/16.
//  Copyright © 2016 Hugues Bernet-Rollande. All rights reserved.
//

import UIKit
import SSZipArchive

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var progress: UIProgressView!
    @IBOutlet weak var button: UIButton!
    @IBOutlet weak var binaryLabel: UILabel!
    @IBOutlet weak var datLabel: UILabel!
    
    var binaryURL: NSURL? = nil {
        didSet {
            print("set binary:", binaryURL)
            let valid = binaryURL != nil ? "valid" : "invalid"
            binaryLabel.text = "Binary: \(valid)"
            refreshState()
        }
    }
    
    var datURL: NSURL? = nil {
        didSet {
            print("set dat:", datURL)
            let valid = datURL != nil ? "valid" : "invalid"
            datLabel.text = "Dat: \(valid)"
            refreshState()
        }
    }
    
    var peripheral: CBPeripheral? = nil {
        didSet {
            print("set peripheral:", peripheral)
            refreshState()
        }
    }
    
    var scanner: BLEScanner!
    
    var otaManager: OTAManager?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        button.enabled = false
        progress.progress = 0
        
        scanner = BLEScanner() { [weak self] (peripheral, central) in
//            print("detected", peripheral)
            self?.addPeripheral(peripheral)
        }
        scanner.start()
        
        NSNotificationCenter.defaultCenter().addObserverForName("OpenURL", object: nil, queue: nil) { [weak self] (notification) in
            print("received notification")
            
            guard let info = notification.userInfo else {
                print("invalid notification")
                return
            }
            guard let url = info["url"] as? NSURL else {
                print("missing notification url")
                return
            }
            
            self?.extractZip(url)
        }
    }
    
    func addPeripheral(peripheral: CBPeripheral) {
        if peripherals.contains(peripheral) { return }
        peripherals.append(peripheral)
        tableView.reloadData()
    }
    
    // MARK: Actions
    
    @IBAction func update(sender: UIButton) {
        sender.enabled = false
        otaManager?.start()
    }
    
    // MARK: Helpers
    
    func refreshState() {
        guard let binaryURL = binaryURL else {
            print("missing application.bin")
            return
        }
        
        guard let datURL = datURL else {
            print("missing application.dat")
            return
        }
        
        guard let peripheral = peripheral else {
            print("missing peripheral")
            return
        }
        
        if let otaManager = OTAManager(binaryURL: binaryURL, dataURL: datURL, centralManager: scanner.centralManager, peripheral: peripheral) {
            
            otaManager.progressBlock = { [weak self] (p) in
                self?.progress.progress = p
            }
            
            otaManager.didChangeStateBlock = { [weak self] (state) in
                switch state {
                case .Completed, .Failed:
                    self?.button.enabled = true
                default:
                    break
                }
            }
            
            self.otaManager = otaManager
            
            button.enabled = true
            
        } else {
            print("invalid")
        }
    }
    
    var documentsURL: NSURL? {
        let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        return urls.first
        
    }
    
    func extractZip(url: NSURL) {
        print("url:", url)
        
        guard let documentsURL = documentsURL else {
            print("unable to find documents url")
            return
        }
        
        if SSZipArchive.unzipFileAtPath(url.path!, toDestination: documentsURL.path!) {
            print("files extracted")
            checkDocumentFiles()
        } else {
            print("Unable to extract zip")
        }
    }
    
    func checkDocumentFiles() {
        let fileManager = NSFileManager.defaultManager()
        
        guard let documentsURL = documentsURL else {
            print("unable to find documents url")
            return
        }
        
        guard let binaryURL = documentsURL.URLByAppendingPathComponent("application.bin") where fileManager.fileExistsAtPath(binaryURL.path!) else {
            print("no binary")
            return
        }
        self.binaryURL = binaryURL
        
        guard let datURL = documentsURL.URLByAppendingPathComponent("application.dat") where fileManager.fileExistsAtPath(binaryURL.path!) else {
            print("no dat")
            return
        }
        self.datURL = datURL
    }
    
    // MARK: UITableViewControllerDelegate
    
    var peripherals: [CBPeripheral] = []
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return peripherals.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("cell", forIndexPath: indexPath)
        let peripheral = peripherals[indexPath.row]
        cell.textLabel?.text = peripheral.name ?? "Unknown"
//        cell.detailTextLabel?.text = String(peripheral.RSSI)
        cell.detailTextLabel?.text = ""
        return cell
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        self.peripheral = peripherals[indexPath.row]
    }
}

//
//  OTAManager.swift
//  MAPO
//
//  Created by Hugues Bernet-Rollande on 27/9/16.
//  Copyright © 2016 WB Technologies. All rights reserved.
//

import iOSDFULibrary
import Foundation
import CoreBluetooth


class BLEScanner: NSObject, CBCentralManagerDelegate {
    typealias DetectionBlock = (peripheral: CBPeripheral, central: CBCentralManager) -> Void
    var detectionBlock: DetectionBlock? = nil
    var centralManager: CBCentralManager! = nil
    
    typealias StateUpdatedBlock = (ready: Bool) -> Void
    var stateUpdatedBlock: StateUpdatedBlock? = nil
    
    enum State {
        case Scanning, Idle
    }
    var state: State = .Idle
    
    init(detectionBlock: DetectionBlock) {
        self.detectionBlock = detectionBlock
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK CBCentralManagerDelegate
    @objc func centralManagerDidUpdateState(central: CBCentralManager) {
        print("centralManagerDidUpdateState:", central.state.rawValue)
        
        switch(central.state) {
        case .PoweredOn:
            if state == .Scanning {
                startScan()
            }
        default:
            stateUpdatedBlock?(ready: false)
            break
        }
    }
    
    @objc func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
//        print("didDiscoverPeripheral:", peripheral)
        detectionBlock?(peripheral: peripheral, central: central)
    }
    
    func stop() {
        state = .Idle
        centralManager.stopScan()
    }
    
    func start() {
        state = .Scanning
        if centralManager.state == .PoweredOn {
            startScan()
        }
    }
    
    private func startScan() {
        centralManager.scanForPeripheralsWithServices([], options: nil)
    }
}



class OTAManager: DFUServiceDelegate, LoggerDelegate, DFUProgressDelegate {
    let firmware: DFUFirmware
    
    var controller: DFUServiceController? = nil
    var initiator: DFUServiceInitiator! = nil
    
    typealias DidChangeStateBlock = (state: DFUState) -> Void
    var didChangeStateBlock: DidChangeStateBlock? = nil
    
    typealias ProgressBlock = (progress: Float) -> Void
    var progressBlock: ProgressBlock? = nil
    
    var attempt: Int = 3
    
    init?(binaryURL: NSURL, dataURL: NSURL, centralManager: CBCentralManager, peripheral: CBPeripheral, attempt: Int = 3) {
        self.attempt = attempt
        
        guard let firmware = DFUFirmware(urlToBinOrHexFile: binaryURL, urlToDatFile: dataURL, type: DFUFirmwareType.Application) else {
            print("invalid firmware")
            return nil
        }
        
        self.firmware = firmware
        
        initiator = DFUServiceInitiator(centralManager: centralManager, target: peripheral).withFirmwareFile(firmware)
        initiator.logger = self; // - to get log info
        initiator.delegate = self; // - to be informed about current state and errors
        initiator.progressDelegate = self; // - to show progress bar
    }
    
    func start() {
        print("update")
        
        controller = initiator?.start()
    }
    
    // MARK LoggerDelegate
    @objc func didStateChangedTo(state: DFUState) {
        print("didStateChangedTo:", state.description())
        
        didChangeStateBlock?(state: state)
    }
    
    @objc func didErrorOccur(error: DFUError, withMessage message: String) {
        print("didErrorOccur:", error.rawValue, message)
        
        switch error {
        case .DeviceDisconnected:
            guard attempt > 1 else {
                return
            }
            attempt -= 1
            print("restarting")
            start()
            break
        default:
            break
        }
    }
    
    // MARK DFUProgressDelegate
    @objc func onUploadProgress(part: Int, totalParts: Int, progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        progressBlock?(progress: Float(progress) / 100)
    }
    
    // MARK LoggerDelegate
    @objc func logWith(level: LogLevel, message: String) {
        if message.containsString("Data written") { return }
        
        print("Log:", String(level.rawValue), message)
    }
}
