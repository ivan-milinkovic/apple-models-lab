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

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class CameraUIView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var cameraLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> UIView {
        let view = CameraUIView()
        view.cameraLayer.session = session
        view.cameraLayer.videoGravity = .resizeAspect//Fill
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let cameraView = uiView as? CameraUIView else { return }
        cameraView.cameraLayer.session = session
    }
}

#elseif os(macOS)

import AppKit

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    final class CameraNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = CameraNSView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let cameraView = nsView as? CameraNSView else { return }
        cameraView.previewLayer.session = session
    }
}
#endif
