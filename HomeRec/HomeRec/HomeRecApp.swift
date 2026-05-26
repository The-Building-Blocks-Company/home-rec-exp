//
//  HomeRecApp.swift
//  HomeRec
//
//  Created by Melissa de Britto Pereira on 10/01/26.
//

import SwiftUI
import CoreText
import os

@main
struct HomeRecApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = RecorderViewModel()

    init() {
        // Register custom fonts from the app bundle
        Self.registerCustomFonts()
    }

    private static func registerCustomFonts() {
        let fontFiles = ["Archivo-Variable", "Inter"]
        for fontName in fontFiles {
            guard let fontURL = Bundle.main.url(forResource: fontName, withExtension: "ttf") else {
                Log.recorder.error("Font resource not found in bundle: \(fontName, privacy: .public).ttf")
                continue
            }
            var errorRef: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &errorRef) {
                let error = errorRef?.takeRetainedValue()
                Log.recorder.error("Failed to register font \(fontName, privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
            }
        }
    }

    var body: some Scene {
        WindowGroup("Home Rec") {
            RecorderView()
                .environmentObject(viewModel)
                .onAppear {
                    // Wire up the menu bar controller with the shared view model
                    if appDelegate.menuBarController == nil {
                        appDelegate.menuBarController = MenuBarController(viewModel: viewModel)
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}
