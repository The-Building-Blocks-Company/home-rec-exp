//
//  InfoPlistTests.swift
//  HomeRecTests
//
//  BL-084: guards the bundle's Info.plist against silent drift.
//
//  These run against the *host app's built bundle*, not the repo — which is the
//  whole point. A checked-in Info.plist sat in this project for months looking
//  authoritative while contributing nothing to the product: `INFOPLIST_FILE` was
//  never set and `GENERATE_INFOPLIST_FILE` was on, so Xcode synthesised the real
//  plist and ignored the file. Two keys that appeared present in the repo
//  (`NSMicrophoneUsageDescription`, `NSAppleEventsUsageDescription`) were absent
//  from every shipped build. Asserting against the repo would have reproduced the
//  same blind spot, so every check here reads the product.
//

import Testing
import Foundation
@testable import HomeRec

@MainActor
struct InfoPlistTests {

    /// The host app's bundle. Unit tests are injected into the app via `TEST_HOST`,
    /// so `Bundle.main` is the app being shipped, not the test bundle.
    private var appBundle: Bundle { Bundle.main }

    private func string(_ key: String) -> String? {
        appBundle.object(forInfoDictionaryKey: key) as? String
    }

    @Test("Bundle identity keys are present in the built product")
    func identityKeysPresent() throws {
        #expect(string("CFBundleIdentifier") == "com.mdebritto.HomeRec")
        #expect(string("CFBundleDisplayName") == "Home Rec")
        #expect(try #require(string("CFBundleShortVersionString")).isEmpty == false)
        #expect(try #require(string("CFBundleVersion")).isEmpty == false)
    }

    /// `LSMinimumSystemVersion` is synthesised from `MACOSX_DEPLOYMENT_TARGET`.
    /// The v1.1 capture work (BL-100/130) relies on macOS 15-only ScreenCaptureKit
    /// API, so a silent downgrade here would produce a bundle that launches on a
    /// system where those calls are unavailable.
    @Test("Deployment floor is macOS 15.0")
    func minimumSystemVersionIsFifteen() {
        #expect(string("LSMinimumSystemVersion") == "15.0")
    }

    /// Regression guard for the defect BL-084 fixed. The repo's `Info.plist` was
    /// not wired in as the bundle's plist, but it *was* picked up as a resource by
    /// the file-system-synchronized group — so every build, including shipped v1.0,
    /// carried a second `Info.plist` under `Contents/Resources/` that macOS never
    /// reads. Restoring any stray plist there would resurrect the same confusion.
    @Test("No stray Info.plist shipped under Contents/Resources")
    func noStrayResourceInfoPlist() {
        let stray = appBundle.url(forResource: "Info", withExtension: "plist")
        #expect(stray == nil, "Found an Info.plist in Resources — macOS ignores it; delete it.")
    }

    /// Usage-description strings must live in the *product*, not merely in the repo.
    /// macOS terminates a process that requests a protected resource without the
    /// matching key, so a key that is present in a file but absent from the bundle
    /// is a crash waiting on the feature that needs it.
    ///
    /// Home Rec requests no protected resource whose string it must declare today:
    /// Screen Recording is gated by TCC without a required purpose string (BL-080
    /// adds `NSScreenCaptureUsageDescription` for honesty, not necessity), and
    /// microphone access does not exist until BL-130. Each of those items extends
    /// the list below as it lands.
    @Test("Declared usage descriptions match what the app actually requests")
    func usageDescriptionsMatchCapabilities() {
        // Deliberately empty: declaring a permission the app never requests would
        // contradict the product's own permission-honesty positioning. BL-080 adds
        // NSScreenCaptureUsageDescription; BL-130 adds NSMicrophoneUsageDescription.
        let required: [String] = []
        for key in required {
            #expect(string(key)?.isEmpty == false, "Missing usage description: \(key)")
        }

        // The reverse guard: nothing the app cannot justify. NSAppleEventsUsageDescription
        // was carried in the dead file for months with no AppleEvents code anywhere.
        #expect(string("NSAppleEventsUsageDescription") == nil)
    }
}
