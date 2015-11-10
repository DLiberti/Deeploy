//
//  ViewController.swift
//  Deeploy
//
//  Created by Libertino, Dino on 25/03/15.
//  Copyright (c) 2015 Dino Libertino. All rights reserved.
//

import Cocoa
import AppKit
import Foundation
import ServiceManagement
import Darwin

class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet weak var TableView: NSTableView!
    @IBOutlet weak var progressLabel: NSTextField!
    @IBOutlet weak var updateGear: NSProgressIndicator!
    @IBOutlet weak var daysLeftLabel: NSTextField!
    
    //Button Outlets
    @IBOutlet weak var runAtLogoutButtonLabel: NSButton!
    @IBOutlet weak var updateNowButtonLabel: NSButton!
    @IBOutlet weak var checkUpdateButtonLabel: NSButton!
    @IBOutlet weak var quitButtonLabel: NSButton!
    
    //Singleton to access AppDelegate
    let appDelegate : AppDelegate = AppDelegate().sharedInstance()
    
    var appArray:[AppModel] = []
    //var currentAppArray: [AppModel] = []
    var appToUpdate: [AppModel] = []
    var localPrefArray:NSDictionary = NSDictionary()
    var serverURL: String = ""
    var hostName: String = ""
    var installDir: String = ""
    var listenerDir: String = ""
    
    //LocalPrefences
    var localUserPreferecesArray:NSDictionary = NSDictionary()
    var daysLeft: Int = 0
    var updatesAvailable:Int = 0
    
    //Library Files & Folders
    let libraryFolder: String = "/Library/Deeploy"
    let localPrefPlist = "/Library/Deeploy/Resources.plist"
    let applicationSupportInstallerFolder: String = "/usr/local/deeploy/installer/"
    let applicationSupportInstallerScript: String = "/usr/local/deeploy/installer/deeploy.installer"
    let applicationSupportRunScript: String = "/usr/local/deeploy/installer/deeploy.logout"
    let localDeeployPreferencePlist: String = "/Library/Preferences/com.disney.deeploy"
    let logFile: String = "/Users/Shared/Deeploy/deeploy.log"
    
    //run files
    let installerFile: String = "com.disney.deeploy.installer"
    let runFile: String = "com.disney.deeploy.run"
    
    //Local Catalog
    var remoteProductionCatalog: String = ""
    var currentProductionCatalog: String = ""
    var temporaryProductionCatalog: String = ""
    var productionCatalogName:String = ""
    var updateArray:NSDictionary = NSDictionary()
    
    override func viewDidLoad() {
        if #available(OSX 10.10, *) {
            super.viewDidLoad()
        } else {
            // Fallback on earlier versions
        }
        
        // Do any additional setup after loading the view.
    }
    
    override var representedObject: AnyObject? {
        didSet {
            // Update the view, if already loaded.
            
        }
    }
    
    func exitFromApp() {
        
        let exitCode: Int = 1
        if exitCode == 1 {
            exit(0)
        }
        
    }
    
    func main() {
        
        //async to load quickly run the view and executing the compare in background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), {
            self.folderStructureCheckAndLoadPrefereces()
            self.loadLocalUserPreferences()
            self.serverIsReachable()
            self.downloadProductionCatalog()
            // se non esce per mancanza di update, mostraimo la finestra e andiamo avanti
            self.daysLeftCheck()
            self.updateGear.displayedWhenStopped = false
            self.updateGear.startAnimation(self)
            self.updateProgessLabel(message: "Checking installed applications")
            self.loadUpdateArray()
            self.listApplications()
            self.internetPluginInstalled()
            self.listUpdate()
            
            if self.appToUpdate.count > 0 {
                self.writeLocalPreferenceInt(theValue: 1, theKey: "UpdatesAvailable")
                self.updateProgessLabel(message: "There is/are \(self.appToUpdate.count) available updates for your computer")
            }
                
            else {
                self.writeLocalPreferenceInt(theValue: 0, theKey: "UpdatesAvailable")
                self.updateProgessLabel(message: "All your applications are up-to-date")
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                //println("main queue, after the previous block")
                self.updateGear.stopAnimation(self)
                self.TableView.reloadData()
                self.appDelegate.window.makeKeyAndOrderFront(self)
            })
        })
        
    }
    
    func printTimestamp() -> String {
        let timestamp = NSDateFormatter.localizedStringFromDate(NSDate(), dateStyle: .MediumStyle, timeStyle: .ShortStyle)
        let currentTime = String(timestamp)
        
        return currentTime
    }
    
    func writeLog(message theMessage:String) {
        
        let currentTimestamp = printTimestamp()
        let fileManager = NSFileManager.defaultManager()
        let message:NSString = ("\(currentTimestamp) -> \(theMessage)")
        
        if fileManager.fileExistsAtPath(logFile) {
            do {
                try message.writeToFile(logFile, atomically: true, encoding: NSUTF8StringEncoding)
            } catch let error as NSError! {
                print(error)
            }
        } else {
            
         fileManager.createFileAtPath(logFile, contents: nil, attributes: nil)
            do {
                try theMessage.writeToFile(logFile, atomically: true, encoding: NSUTF8StringEncoding)
            } catch let error as NSError! {
                print(error)
            }
        }
    }
    
    func initializePreferences() -> NSURL? {
        
        let fileManager = NSFileManager.defaultManager()
        let pathToLibrary: String = "/Users/Shared/"
        let urlToLibrary: NSURL = NSURL(fileURLWithPath: pathToLibrary)
        if let libraryDirectory:NSURL = urlToLibrary as NSURL!{
            print(libraryDirectory)
            let prefDirectory = libraryDirectory.URLByAppendingPathComponent("Deeploy", isDirectory: true)
            let finalPlistPath = prefDirectory.URLByAppendingPathComponent("com.disney.Deeploy.plist")
            var theError: NSError?
            if finalPlistPath.checkResourceIsReachableAndReturnError(&theError) {
                self.changePermission(targetURL: finalPlistPath)
                return finalPlistPath
                
            } else {
                if let bundleURL = NSBundle.mainBundle().URLForResource("com.disney.Deeploy", withExtension: "plist") {
                    do {
                        try fileManager.copyItemAtURL(bundleURL, toURL: finalPlistPath)
                        self.changePermission(targetURL: finalPlistPath)
                        return finalPlistPath
                    } catch let error as NSError {
                        print("Error: \(error)")
                        exit(1)
                    }
                } else {
                        print("Couldn't find initial plist in the bundle!")
                    exit(1)
                    }
                }
            } else {
                print("Couldn't get documents directory!")
                exit(1)
        }
    
        return nil
    }
    
    func changePermission(targetURL targetURL: NSURL) {
        
        let targetPreferenceToString:String = targetURL.path!
        
        let task = NSTask()
        task.launchPath = "/bin/chmod"
        task.arguments = ["-R", "777", targetPreferenceToString]
        
        // Pipe the standard out to an NSPipe, and set it to notify us when it gets data
        let pipe = NSPipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        let exitStatus = task.terminationStatus
        
        if exitStatus == 0 {
            print("\(targetPreferenceToString) changed")
        }
            
        else {
            print("\(targetPreferenceToString) not changed")
        }
    }
    
    func loadLocalUserPreferences() {
    
        let localPref: NSURL! = initializePreferences()
        let localPreferencesToString: String! = localPref.path //trasforma un NSUrl in Path (senza il parametro file:// dell'NSURL)
        print(localPreferencesToString)
        let fileManager = NSFileManager.defaultManager()
        
        if fileManager.fileExistsAtPath(localPreferencesToString) {
            print("fileIsThere")
            
            localUserPreferecesArray = NSDictionary(contentsOfFile: localPreferencesToString)!
            daysLeft = localUserPreferecesArray["DaysLeftBeforeUpdate"] as! Int
            updatesAvailable = localUserPreferecesArray["UpdatesAvailable"] as! Int
            
        }
        else {
            print("fileIsNotThereBUtShoudlBe")
        }
    }
    
    func daysLeftCheck() {
        
        if daysLeft > 0 {
            daysLeftLabel.integerValue = daysLeft
            }
        else {
            daysLeftLabel.integerValue = daysLeft
            daysLeftLabel.textColor = NSColor.redColor()
            self.quitButtonLabel.enabled = false
            self.runAtLogoutButtonLabel.enabled = false
            self.checkUpdateButtonLabel.enabled = false
        }
    }
    
    
    func writeLocalPreferenceInt(theValue theValue:Int, theKey:String) {
            
            let localPref: NSURL! = initializePreferences()
            let localPreferencesToString: String! = localPref.path
            let fileManager = NSFileManager.defaultManager()
            
            if fileManager.fileExistsAtPath(localPreferencesToString) {
                
                localUserPreferecesArray = NSDictionary(contentsOfFile: localPreferencesToString)!
                localUserPreferecesArray.setValue(theValue, forKey: theKey)
                localUserPreferecesArray.writeToFile(localPreferencesToString, atomically: false)
                
            }
            else {
                print("Can't set the preferences")
            }
    }
    
    func writeLocalPreferenceString(theValue theValue:String, theKey:String) {
        
        let localPref: NSURL! = initializePreferences()
        let localPreferencesToString: String! = localPref.path
        let fileManager = NSFileManager.defaultManager()
        
        if fileManager.fileExistsAtPath(localPreferencesToString) {
            
            localUserPreferecesArray = NSDictionary(contentsOfFile: localPreferencesToString)!
            localUserPreferecesArray.setValue(theValue, forKey: theKey)
            localUserPreferecesArray.writeToFile(localPreferencesToString, atomically: false)
            
        }
        else {
            print("Can't set the preferences")
        }
    }
    
    func folderStructureCheckAndLoadPrefereces() {
        
        let fileManager = NSFileManager.defaultManager()
        
        if fileManager.fileExistsAtPath(localPrefPlist) {
            
            localPrefArray = NSDictionary(contentsOfFile: localPrefPlist)!
            serverURL = localPrefArray["ServerRepoURL"] as! String
            remoteProductionCatalog = localPrefArray["RemoteProductionCatalog"] as! String
            hostName = localPrefArray["HostName"] as! String
            installDir = localPrefArray["InstallDirectory"] as! String
            listenerDir = localPrefArray["ListenerDirectory"] as! String
            currentProductionCatalog = localPrefArray["CurrentProdutionCatalog"] as! String
            temporaryProductionCatalog = localPrefArray["TemporaryProductionCatalog"] as! String
            productionCatalogName = localPrefArray["ProductionCatalog"] as! String
            
        }
            
        else {
            print("File preferences not avaialble")
        }
        
        var isDir: ObjCBool = false
        //let's check the application folders structure
        if fileManager.fileExistsAtPath(installDir, isDirectory: &isDir) {
            print("\(installDir) -> OK")
        }
        else {
            do {
                try fileManager.createDirectoryAtPath(installDir, withIntermediateDirectories: true, attributes: nil)
            } catch let error as NSError {
                print("Error: \(error)")
            }
        }
        if fileManager.fileExistsAtPath(listenerDir, isDirectory: &isDir) {
            print("\(listenerDir) -> OK")
        }
        else {
            do {
                try fileManager.createDirectoryAtPath(listenerDir, withIntermediateDirectories: true, attributes: nil)
            } catch let error as NSError {
                print("Error: \(error)")
            }
        }
        
        if fileManager.fileExistsAtPath("/Library/LaunchDaemons/com.disney.deeploy.listener.plist") {
            print("com.disney.deeploy.listener.plist -> OK")
        }
        else {
            print("com.disney.deeploy.listener.plist -> KO")
            exit(1)
        }
        
        if fileManager.fileExistsAtPath(applicationSupportInstallerScript) {
            print("\(applicationSupportInstallerScript) -> OK")
        }
        else {
            print("\(applicationSupportInstallerScript) -> KO")
            exit(1)
        }
        if fileManager.fileExistsAtPath(applicationSupportRunScript) {
            print("\(applicationSupportRunScript) -> OK")
        }
        else {
            print("\(applicationSupportRunScript) -> KO")
            exit(1)
        }
        
    }
    
    func serverIsReachable() {
        
        let task = NSTask()
        task.launchPath = "/sbin/ping"
        task.arguments = ["-q", "-c 3", hostName]
        
        // Pipe the standard out to an NSPipe, and set it to notify us when it gets data
        let pipe = NSPipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        let exitStatus = task.terminationStatus
        
        if exitStatus == 0 {
            print("\(hostName) is avaialble")
        }
            
        else {
            print("\(hostName) in not avaialble")
            sleep(3)
            exit(1)
        }
    }
    
    func downloadProductionCatalog() {
        
        self.fileDownlaod(serverUrl: serverURL, filePath: remoteProductionCatalog, localFolder: "/tmp/")
        //change the path to NSUrl to use the changePrevileges method
        
        let fileManger = NSFileManager.defaultManager()
        //change the path to NSURL to use the changePrevileges method, boring I know
        let temporaryProductionCatalogToUrl = NSURL(fileURLWithPath: temporaryProductionCatalog)
        changePermission(targetURL: temporaryProductionCatalogToUrl)
        
        if fileManger.fileExistsAtPath(currentProductionCatalog) {
        
            //se il catalogo c'è verifichiamo se è lo stesso
            let success = fileManger.contentsEqualAtPath(temporaryProductionCatalog as String, andPath: currentProductionCatalog as String)
            
            if success {
                //se è uguale verifichiamo se lo user ha skippato l'update == 1 nelle preferenze oppure non ci sono update == 0 e si esce
                if updatesAvailable == 0 {
                    //se non ci sono update
                    print("no updates available")
                    exit(0)
                }
                
                else {
                    print("update avaialabe let's go ahead")
                }
            }
            
            else {
                //il catalogo è nuovo
                do {
                    try fileManger.removeItemAtPath(currentProductionCatalog)
                    try fileManger.copyItemAtPath(temporaryProductionCatalog, toPath: currentProductionCatalog)
                } catch let removeError as NSError {
                    print("Error: \(removeError)")
                }
            }
        }
        else {
            
            do {
                try fileManger.copyItemAtPath(temporaryProductionCatalog, toPath: currentProductionCatalog)
            } catch let error as NSError {
                print("Error: \(error)")
            }
        }
    }
    
    
    func loadUpdateArray() {
        
        let fileManager = NSFileManager.defaultManager()
        if fileManager.fileExistsAtPath(currentProductionCatalog) {
            
            updateArray = NSDictionary(contentsOfFile: currentProductionCatalog)!
            print(updateArray)
        }
        else {
            print("Local Production Catalog not Available")
            exit(0)
        }
        
    }
    
    func fileDownlaod(serverUrl serverUrl: String, filePath: String, localFolder: String) {
        
        //let filePathNormalized = filePath.stringByAddingPercentEscapesUsingEncoding(NSUTF8StringEncoding)
        let filePathString = "\(serverUrl)/\(filePath)"
        let filePathStringUrl:NSURL = NSURL(fileURLWithPath: filePathString)
        let fileName = filePathStringUrl.lastPathComponent!
        //updateProgessLabel(message: "Downloading \(fileName)")
        let localFilePathString = "\(localFolder)\(fileName)"
        let url = NSURL(string: filePathString)
        let fileDataFromURL = NSData(contentsOfURL: url!)
        
        let fileManager = NSFileManager.defaultManager()
        fileManager.createFileAtPath(localFilePathString, contents: fileDataFromURL, attributes: nil)
        
    }
    
    func fileUntar(fileName fileName: String, localFolder: String) {
        
        let fileManager = NSFileManager.defaultManager()
        
        let filePath = "\(localFolder)/\(fileName)"
        if fileManager.fileExistsAtPath(filePath) {
            updateProgessLabel(message: "Uncompressing \(fileName)")
            let task = NSTask()
            task.currentDirectoryPath = localFolder
            task.launchPath = "/usr/bin/tar"
            task.arguments = ["-xf", fileName]
            task.launch()
            task.waitUntilExit()
            
            do {
                try fileManager.removeItemAtPath(filePath)
            } catch let removeError as NSError {
                print("Error: \(removeError)")
            }

            
        }
        else {
            print("No \(fileName) to untar")
        }
    }
    
    func activateListener(theListener theListener: String) {
        
        let filePathString = "\(listenerDir)\(theListener)"
        let fileManager = NSFileManager()
        fileManager.createFileAtPath(filePathString, contents: nil, attributes: nil)
        
        if theListener == installerFile {
            
            updateProgessLabel(message: "Update in progress")
            updateGear.startAnimation(self)

            while fileManager.fileExistsAtPath(filePathString) {
                //updateProgessLabel(message: "Update in progress")
                //updateGear.startAnimation(self)
                //in modulo Darwin posso usare sleep
                sleep(2)
                print("listener still present")
            }
            
        }
        //chiamiamo l'end of update per aggiornare campi e preferenze
        self.endOfUpdate()
        
    }
    
    func checkOpenApplications(theApp theApp: String) -> Int {
        
        let bundle = NSBundle.mainBundle()
        let cmd = bundle.pathForResource("ps", ofType: "sh")
        
        let task = NSTask()
        task.launchPath = cmd!
        task.arguments = [theApp]
        
        let pipe = NSPipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        var myValue: Int
        
        if task.terminationStatus == 0 {
            myValue = 0
        }
        else {
            myValue = 1
        }
        
        return myValue
    }
    
    func updateProgessLabel(message message: String) {
        progressLabel.stringValue = message
    }
    
    
    func showMyAlert(myMessage myMessage:String) {
        
        let myAlert:NSAlert = NSAlert()
        myAlert.addButtonWithTitle("OK")
        //myAlert.addButtonWithTitle("Cancel")
        myAlert.messageText = myMessage
        myAlert.runModal()
        
    }
    
    
    func versionsCompare(app app:String, clientVers:String, serverVers:String) -> Int {
        
        func charCleaner(rawVers rawVers: String) -> String {
            
            let range = rawVers.startIndex..<rawVers.endIndex
            let cleanVers = rawVers.stringByReplacingOccurrencesOfString("[a-z]", withString: ".", options: .RegularExpressionSearch, range: range)
            
            return cleanVers
            
        }
        //let's clean the version just in case bloody shockwave
        let clientVersCleaned = charCleaner(rawVers: clientVers)
        let serverVersCleaned = charCleaner(rawVers: serverVers)
        
        //splits at any dot
        var serverVersionSplit = serverVersCleaned.characters.split {$0 == "."}.map { String($0) }
        var clientVersionSplit = clientVersCleaned.characters.split {$0 == "."}.map { String($0) }
        
        //println("\(serverVersionSplit), \(clientVersionSplit)")
        
        //append a 0 in case one of the verison is shorter
        
        let clientIndex = clientVersionSplit.count
        let serverIndex = serverVersionSplit.count
        
        if clientIndex < serverIndex {
            print("client index < server index")
            let indexToAdd = serverIndex - clientIndex
            print("questo è : \(indexToAdd)")
            for index in 1...indexToAdd {
                print("number of 0 to add: \(index)")
                clientVersionSplit.append("0")
                print("\(clientVersionSplit)")
            }
        }
        
        else if clientIndex > serverIndex {
            print("client index > server index")
            let indexToAdd = clientIndex - serverIndex
            print("\(indexToAdd)")
            for index in 1...indexToAdd {
                print("number of 0 to add: \(index)")
                serverVersionSplit.append("0")
                print("\(clientVersionSplit)")
            }
        }
        else {
            print("indexed are equal so let's go")
        }
        
        print("\(serverVersionSplit), \(clientVersionSplit)")
        
        var myValue = 0
        
        for index in 0..<clientVersionSplit.count {
            
            let clientInt:Int = Int(clientVersionSplit[index])!
            let serverInt:Int = Int(serverVersionSplit[index])!
            
            if serverInt > clientInt {
                print("\(serverInt) maggiore di \(clientInt): installa")
                myValue = 1
                break
            }
                
            else if serverInt < clientInt {
                print("\(serverInt) minore di \(clientInt): non installa")
                myValue = 0
                break
                
            }
                
            else {
                print("\(serverInt) uguale a \(clientInt): non installa")
                myValue = 0
            }
        }
        return myValue
    }
    
    
    func listUpdate() {
        
        for (myApp, myVers) in updateArray as NSDictionary! {
            for (key, value) in myVers as! NSDictionary {
                print(key, value)
                if key as! NSString == ("version") {
                    let serverVers = value as! NSString
                    let serverApp = myApp as! NSString
                    for index in 0..<appArray.count {
                        let clientApp = appArray[index].app
                        let clientVers = appArray[index].vers
                        if clientApp == serverApp {
                            let myValue = versionsCompare(app: serverApp as String, clientVers: clientVers as String, serverVers: serverVers as String)
                            if myValue == 1 {
                                print("my value \(myValue)")
                                let updateTask = AppModel(app: serverApp as String, vers: serverVers as String, logout: "Preview")
                                appToUpdate.append(updateTask)
                                print(appToUpdate.count)
                                
                            }
                        }
                    }
                    
                }
            }
            
        }
    }
    

    func internetPluginInstalled() {
        
        let fileManager = NSFileManager.defaultManager()
        let pluginPath = ("/Library/Internet Plug-Ins")
        
        
        do {
            let pluginArray = try fileManager.contentsOfDirectoryAtPath(pluginPath)
            for item in pluginArray {
                let theItem = item
                //let urlToLibrary: NSURL = NSURL(fileURLWithPath: pathToLibrary)
                let urlTheItem: NSURL = NSURL(fileURLWithPath: theItem)
                let urlTheItemExtension = urlTheItem.pathExtension
                if urlTheItemExtension == ("plugin") {
                    let filePath = ("\(pluginPath)/\(theItem)/Contents/Info.plist")
                    if fileManager.fileExistsAtPath(filePath) {
                        let infoDict = NSDictionary(contentsOfFile: filePath)
                        if infoDict!["CFBundleVersion"] != nil {
                            let appVersion = infoDict!["CFBundleVersion"] as! String
                            print(appVersion)
                            //instanzio il modello e lo infilo nell'array
                            let appName = NSString(string: theItem).stringByDeletingPathExtension
                            let appTask = AppModel(app: appName, vers: appVersion, logout: "no")
                            print(appName, appVersion)
                            //aggiungo all'arrary
                            appArray.append(appTask)
                        }
                    }
                }
            }
        } catch let error as NSError {
            print(error)
        }
        
        do {
            let pluginArray = try fileManager.contentsOfDirectoryAtPath(pluginPath)
            for item in pluginArray {
                let theItem = item
                //let urlToLibrary: NSURL = NSURL(fileURLWithPath: pathToLibrary)
                let urlTheItem: NSURL = NSURL(fileURLWithPath: theItem)
                let urlTheItemExtension = urlTheItem.pathExtension
                if urlTheItemExtension == ("webplugin") {
                    let filePath = ("\(pluginPath)/\(theItem)/Contents/Info.plist")
                    if fileManager.fileExistsAtPath(filePath) {
                        let infoDict = NSDictionary(contentsOfFile: filePath)
                        if infoDict!["CFBundleVersion"] != nil {
                            let appVersion = infoDict!["CFBundleVersion"] as! String
                            print(appVersion)
                            //instanzio il modello e lo infilo nell'array
                            let appName = NSString(string: theItem).stringByDeletingPathExtension
                            let appTask = AppModel(app: appName, vers: appVersion, logout: "no")
                            print(appName, appVersion)
                            //aggiungo all'arrary
                            appArray.append(appTask)
                        }
                    }
                }
            }
        } catch let error as NSError {
            print(error)
        }
    }
    
    func listApplications() {
        
        let fileManager = NSFileManager.defaultManager()
        let applicationPath = ("/Applications")
        //lista il contenuto di Applications e lo butta in un array
        do {
            let docsArray = try fileManager.contentsOfDirectoryAtPath(applicationPath)
            for item in docsArray {
                let theItem = item
                //let urlToLibrary: NSURL = NSURL(fileURLWithPath: pathToLibrary)
                let urlTheItem: NSURL = NSURL(fileURLWithPath: theItem)
                let urlTheItemExtension = urlTheItem.pathExtension
                if urlTheItemExtension == ("app") {
                    let filePath = ("\(applicationPath)/\(theItem)/Contents/Info.plist")
                    if fileManager.fileExistsAtPath(filePath) {
                        let infoDict = NSDictionary(contentsOfFile: filePath)
                        if infoDict!["CFBundleShortVersionString"] != nil {
                            let appVersion = infoDict!["CFBundleShortVersionString"] as! String
                            print(appVersion)
                            let appName = NSString(string: theItem).stringByDeletingPathExtension
                            let appTask = AppModel(app: appName, vers: appVersion, logout: "no")
                            print(appName, appVersion)
                            //aggiungo all'arrary
                            appArray.append(appTask)
                        }
                    }
                }
                
                if urlTheItemExtension != ("app") {
                    let subAppPath = "\(applicationPath)/\(theItem)"
                    print(subAppPath)
                    //var error: NSError?
                    var isDir = ObjCBool(false)
                    if fileManager.fileExistsAtPath(subAppPath, isDirectory: &isDir) {
                        if isDir.boolValue == true {
                            let SubDocsArray = try fileManager.contentsOfDirectoryAtPath(subAppPath)
                            for subItem in SubDocsArray {
                                let urlOfSubItem:NSURL = NSURL(fileURLWithPath: subItem)
                                let urlOfSubItemExtension = urlOfSubItem.pathExtension
                                if urlOfSubItemExtension == ("app") {
                                    let filePath = ("\(subAppPath)/\(subItem)/Contents/Info.plist")
                                    if fileManager.fileExistsAtPath(filePath) {
                                        let infoDict = NSDictionary(contentsOfFile: filePath)
                                        if infoDict!["CFBundleShortVersionString"] != nil {
                                            let appVersion = infoDict!["CFBundleShortVersionString"] as! String
                                            print(appVersion)
                                            let appName = NSString(string: theItem).stringByDeletingPathExtension
                                            let appTask = AppModel(app: appName, vers: appVersion, logout: "no")
                                            //print(appName, appVersion)
                                            //aggiungo all'arrary
                                            appArray.append(appTask)
                                        }
                                    }
                                }
                            }
                            
                        }
                        
                    }
                }
            }
            
        } catch let error as NSError {
            print(error)
        }
    }
    
    
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        
        return appToUpdate.count
        
    }
    
    func tableView(tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }
    
    func tableView(tableView: NSTableView, shouldSelectTableColumn tableColumn: NSTableColumn?) -> Bool {
        return false
    }
    
    //cellview
    //func tableView(tableView: NSTableView!, objectValueForTableColumn tableColumn: NSTableColumn!, row: Int) -> AnyObject!
    func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject?{
        
        var result = ""
        
        //let's sort it alphabetically
        appToUpdate = appToUpdate.sort() { $0.app < $1.app }
        
        let columnIdentifier = tableColumn!.identifier
        if columnIdentifier == "app" {
            result = appToUpdate[row].app
        }
        if columnIdentifier == "vers" {
            result = appToUpdate[row].vers
        }
        if columnIdentifier == "logout" {
            result = appToUpdate[row].logout
        }
        return result
    }
    
    @IBAction func updateButton(sender: NSButton) {
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), {
            //println("background")
            self.updateGear.startAnimation(self)
            self.runAtLogoutButtonLabel.enabled = false
            self.checkUpdateButtonLabel.enabled = false
            self.updateNowButtonLabel.enabled = false
            self.quitButtonLabel.enabled = false
            
            if self.appToUpdate.count > 0 {
                
                for index in 0..<self.appToUpdate.count {
                    let itemToUpdate = self.appToUpdate[index].app
                    for (item, key) in self.updateArray as NSDictionary {
                        if item as? NSString == itemToUpdate {
                            let itemPs = key["ps"]!! as! NSString
                            //let's check if any single application is open which could interfer with the process
                            //let itemPs = key["ps"]!! as NSString
                            let result = self.checkOpenApplications(theApp: itemPs as String)
                            if result == 0 {
                                print("let's go to install \(item)")
                            }
                            else {
                                var stillOpen = 1
                                while stillOpen == 1 {
                                    
                                    let myAlert:NSAlert = NSAlert()
                                    myAlert.addButtonWithTitle("Continue")
                                    myAlert.addButtonWithTitle("Cancel")
                                    myAlert.messageText = "\(item) is open. Please ensure to close it before to continue"
                                    let result = myAlert.runModal()
                                    
                                    switch(result) {
                                    case NSAlertFirstButtonReturn:
                                        stillOpen = self.checkOpenApplications(theApp: itemPs as String)
                                    case NSAlertSecondButtonReturn:
                                        print("Cancel")
                                        exit(0)
                                    default:
                                        break
                                    }
                                }
                            }
                            
                            let itemUrl = key["url"]!! as! NSString
                            self.fileDownlaod(serverUrl: self.serverURL, filePath: itemUrl as String, localFolder: self.installDir)
                            let fileName = itemUrl.lastPathComponent
                            self.fileUntar(fileName: fileName, localFolder: self.installDir)
                        }
                    }
                }
                self.updateProgessLabel(message: "Installing available updates...")
                self.activateListener(theListener: self.installerFile)
                
                
            }
            else {
                print("All applications are Up-to-date")
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                //println("main queue, after the previous block")
                //la fine dell'update con laggiornamento dei campi verà eseguito dalla funzione EndOFUpdate()
                //dopo l'usicta del white statement in activateListener()
                
            })
        })
        
    }
    
    func endOfUpdate() {
        print("end of update is running")
        self.updateGear.stopAnimation(self)
        self.appToUpdate = []
        self.updateProgessLabel(message: "All avaialable updates have been installed")
        self.TableView.reloadData()
        self.checkUpdateButtonLabel.enabled = true
        self.writeLocalPreferenceInt(theValue: 5, theKey: "DaysLeftBeforeUpdate")
        self.writeLocalPreferenceInt(theValue: 0, theKey: "UpdatesAvailable")
    
    }
    
    @IBAction func checkUpdButton(sender: NSButton) {
        
        //async to load quickly run the view and executing the compare in background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), {
            self.updateGear.startAnimation(self)
            self.runAtLogoutButtonLabel.enabled = false
            self.updateNowButtonLabel.enabled = false
            self.checkUpdateButtonLabel.enabled = false
            self.quitButtonLabel.enabled = false
            self.updateProgessLabel(message: "Checking for available updates")
            self.appArray = []
            self.appToUpdate = []
            self.TableView.reloadData()
            self.serverIsReachable()
            self.downloadProductionCatalog()
            self.loadUpdateArray()
            self.listApplications()
            self.internetPluginInstalled()
            self.listUpdate()

            if self.appToUpdate.count > 0 {
                self.updateProgessLabel(message: "There are \(self.appToUpdate.count) available updates for your computer")
                self.runAtLogoutButtonLabel.enabled = true
                self.updateNowButtonLabel.enabled = true
                self.checkUpdateButtonLabel.enabled = true
                self.quitButtonLabel.enabled = true
                self.writeLocalPreferenceInt(theValue: 1, theKey: "UpdatesAvailable")
            }
            else {
                self.updateProgessLabel(message: "No available updates for your computer")
                self.checkUpdateButtonLabel.enabled = true
                self.runAtLogoutButtonLabel.enabled = false
                self.updateNowButtonLabel.enabled = false
                self.quitButtonLabel.enabled = true
                self.writeLocalPreferenceInt(theValue: 0, theKey: "UpdatesAvailable")
                
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                //println("main queue, after the previous block")
                //self.TableView.reloadData()
                //self.updateGear.stopAnimation(self)

                self.TableView.reloadData()
                self.updateGear.stopAnimation(self)
            })
        })
    }
    
    
    @IBAction func runAtLogout(sender: AnyObject) {
        
        //async to load quickly run the view and executing the compare in background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), {
            //println("background")
            self.updateGear.startAnimation(self)
            
            if self.appToUpdate.count > 0 {
                
                for index in 0..<self.appToUpdate.count {
                    let itemToUpdate = self.appToUpdate[index].app
                    for (item, key) in self.updateArray as NSDictionary {
                        if item as? NSString == itemToUpdate {
                            let itemUrl = key["url"]!! as! NSString
                            self.fileDownlaod(serverUrl: self.serverURL, filePath: itemUrl as String, localFolder: self.installDir)
                            let fileName = itemUrl.lastPathComponent
                            self.fileUntar(fileName: fileName, localFolder: self.installDir)
                        }
                    }
                }
                
                self.activateListener(theListener: self.runFile)
                self.updateProgessLabel(message: "Updates ready to be installed at logout")
                
            }
            else {
                self.showMyAlert(myMessage: "All applications are Up-to-date")
                
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                //println("main queue, after the previous block")
                self.updateGear.stopAnimation(self)
                self.writeLocalPreferenceInt(theValue: 5, theKey: "DaysLeftBeforeUpdate")
                self.writeLocalPreferenceInt(theValue: 0, theKey: "UpdatesAvailable")
            })
        })
    }
    
    @IBAction func quitButton(sender: NSButton) {
        
        if daysLeft > 0 {
            daysLeft = daysLeft - 1
            self.writeLocalPreferenceInt(theValue: daysLeft, theKey: "DaysLeftBeforeUpdate")
            if appToUpdate.count > 0 {
                self.writeLocalPreferenceInt(theValue: 1, theKey: "UpdatesAvailable")
            }
            
            exit(0)
        }
        
        else {
            self.checkUpdateButtonLabel.enabled = false
            self.runAtLogoutButtonLabel.enabled = false
            self.quitButtonLabel.enabled = false
        }
        
    }
    
} //finale