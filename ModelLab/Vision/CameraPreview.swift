//
//  CameraPreview.swift
//  ModelLab
//
//  Created by Ivan Milinkovic on 27. 6. 2026.
//

import SwiftUI
import AVFoundation

final class PointMapper {
    var cameraLayer: AVCaptureVideoPreviewLayer?
    
    func convert(point: CGPoint) -> CGPoint {
        guard let cameraLayer else { return .zero }
        return cameraLayer.layerPointConverted(fromCaptureDevicePoint: point)
    }
}

final class PreviewRotationTracker: @unchecked Sendable {
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?
    private var outputConnection: AVCaptureConnection?

    func start(device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer, outputConnection: AVCaptureConnection?) {
        self.outputConnection = outputConnection
        
        if coordinator == nil {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator
            // Wrap the layer so it isn't captured directly by the @Sendable KVO closure below.
            let wrappedLayer = SendableWrapper(value: previewLayer)
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, change in
                guard let angle = change.newValue else { return }
                DispatchQueue.main.async {
                    Self.apply(angle, toPreview: wrappedLayer.value, andOutput: self?.outputConnection)
                }
            }
        }

        if let coordinator {
            Self.apply(coordinator.videoRotationAngleForHorizonLevelPreview, toPreview: previewLayer, andOutput: outputConnection)
        }
    }

    private static func apply(_ angle: CGFloat, toPreview previewLayer: AVCaptureVideoPreviewLayer, andOutput outputConnection: AVCaptureConnection?) {
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if let outputConnection, outputConnection.isVideoRotationAngleSupported(angle) {
            outputConnection.videoRotationAngle = angle
        }
    }
}

#if os(iOS)

import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let outputConnection: AVCaptureConnection?
    let pointMapper: PointMapper

    final class CameraUIView: UIView {
        let rotationTracker = PreviewRotationTracker()

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
        view.cameraLayer.videoGravity = .resizeAspectFill
        if let device {
            view.rotationTracker.start(device: device, previewLayer: view.cameraLayer, outputConnection: outputConnection)
        }
        pointMapper.cameraLayer = view.cameraLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let cameraView = uiView as? CameraUIView else { return }
        cameraView.cameraLayer.session = session
        if let device {
            cameraView.rotationTracker.start(device: device, previewLayer: cameraView.cameraLayer, outputConnection: outputConnection)
        }
    }
}

#elseif os(macOS)

import AppKit

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let outputConnection: AVCaptureConnection?
    let pointMapper: PointMapper

    final class CameraNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        let rotationTracker = PreviewRotationTracker()

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
        if let device {
            view.rotationTracker.start(device: device, previewLayer: view.previewLayer, outputConnection: outputConnection)
        }
        pointMapper.cameraLayer = view.previewLayer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let cameraView = nsView as? CameraNSView else { return }
        cameraView.previewLayer.session = session
        if let device {
            cameraView.rotationTracker.start(device: device, previewLayer: cameraView.previewLayer, outputConnection: outputConnection)
        }
    }
}
#endif
