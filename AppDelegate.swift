//
//  AppDelegate.swift
//  App Traffic Inspector
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {}
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {}

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        for window in sender.windows {
            window.orderFront(self)
        }
        
        return true
    }
}
