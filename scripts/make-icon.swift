#!/usr/bin/env swift
//
// Renders a SwiftUI view into the macOS AppIcon.iconset format at each
// required (size, scale) pair. Call from make-icon.sh, not directly.
//
// Usage: swift scripts/make-icon.swift <iconset-output-dir>

import Foundation
import SwiftUI
import AppKit

private struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 224, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.60, blue: 0.28),
                            Color(red: 0.86, green: 0.36, blue: 0.17),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Image(systemName: "gauge.with.dots.needle.67percent")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(200)
                .foregroundStyle(.white)
        }
        .frame(width: 1024, height: 1024)
    }
}

private let sizesAtScale: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

@MainActor
private func writePNG(view: some View, width: Int, height: Int, to url: URL) {
    let renderer = ImageRenderer(
        content: view.frame(width: CGFloat(width), height: CGFloat(height))
    )
    renderer.scale = 1.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write("render failed for \(url.lastPathComponent)\n".data(using: .utf8)!)
        exit(2)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: CGFloat(width), height: CGFloat(height))
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("png encode failed for \(url.lastPathComponent)\n".data(using: .utf8)!)
        exit(2)
    }
    try? data.write(to: url, options: .atomic)
}

@MainActor
private func run() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        FileHandle.standardError.write("usage: make-icon.swift <output-iconset-dir>\n".data(using: .utf8)!)
        exit(1)
    }
    let outDir = URL(fileURLWithPath: args[1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let icon = AppIconView()

    for (pt, scale) in sizesAtScale {
        let px = pt * scale
        let name = scale == 1
            ? "icon_\(pt)x\(pt).png"
            : "icon_\(pt)x\(pt)@2x.png"
        writePNG(view: icon, width: px, height: px, to: outDir.appendingPathComponent(name))
        print("wrote \(name)")
    }
}

// swift-run scripts don't support @main on MainActor types in all versions;
// jump onto the main actor synchronously.
DispatchQueue.main.async {
    run()
    exit(0)
}
RunLoop.main.run()
