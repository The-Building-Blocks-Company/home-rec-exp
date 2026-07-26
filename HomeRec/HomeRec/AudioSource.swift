//
//  AudioSource.swift
//  HomeRec
//
//  What to capture audio from (BL-100). `AudioSourceManager` owns selection
//  and persistence; `ScreenCaptureAudioManager` resolves a source into the
//  matching SCContentFilter at capture setup time.
//

import Foundation

enum AudioSource: Codable, Sendable, Equatable {
    case systemAll
    case app(bundleID: String)
}
