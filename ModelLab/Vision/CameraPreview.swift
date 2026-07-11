//
//  CameraPreview.swift
//  ModelLab
//
//  Created by Ivan Milinkovic on 27. 6. 2026.
//

import SwiftUI
import AVFoundation

#if os(iOS)

import UIKit

/// Displays an already-configured AVCaptureVideoPreviewLayer (session, rotation and
/// mirroring all owned and managed by CameraService). This view just hosts the layer.
struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    final class CameraUIView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                guard previewLayer !== oldValue else { return }
                oldValue?.removeFromSuperlayer()
                if let previewLayer {
                    layer.addSublayer(previewLayer)
                    previewLayer.frame = bounds
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }

    func makeUIView(context: Context) -> UIView {
        let view = CameraUIView()
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let cameraView = uiView as? CameraUIView else { return }
        cameraView.previewLayer = previewLayer
    }
}

#elseif os(macOS)

import AppKit

/// Displays an already-configured AVCaptureVideoPreviewLayer (session, rotation and
/// mirroring all owned and managed by CameraService). This view just hosts the layer.
struct CameraPreview: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    final class CameraNSView: NSView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                guard previewLayer !== oldValue else { return }
                oldValue?.removeFromSuperlayer()
                if let previewLayer {
                    layer?.addSublayer(previewLayer)
                    previewLayer.frame = bounds
                }
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = CameraNSView()
        view.previewLayer = previewLayer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let cameraView = nsView as? CameraNSView else { return }
        cameraView.previewLayer = previewLayer
    }
}
#endif
