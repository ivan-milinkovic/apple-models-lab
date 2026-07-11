//
//  CameraService.swift
//  ModelLab
//
//  Created by Ivan Milinkovic on 27. 6. 2026.
//

import Foundation
@preconcurrency import AVFoundation
import Observation

nonisolated struct SendableWrapper<T>: @unchecked Sendable {
    let value: T
}

actor CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private(set) var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var device: AVCaptureDevice?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private let outputQueue = DispatchQueue(label: "camera-output-queue", qos: .userInitiated, autoreleaseFrequency: .workItem)
    
    nonisolated(unsafe) var callback: ((SendableWrapper<CMSampleBuffer>) -> Void)?

    func setup(previewLayer: SendableWrapper<AVCaptureVideoPreviewLayer>) async throws {
        guard session == nil else { return }
        guard try await handleAuthorization() else {
            return
        }
        try setupSession(previewLayer: previewLayer.value)
    }
    
    func setCallback(_ callback: @escaping @Sendable (SendableWrapper<CMSampleBuffer>) -> Void) {
        self.callback = callback
    }
    
    func start() {
        guard let session, !session.isRunning else { return }
        session.startRunning()
        print("Camera started")
    }
    
    func stop() {
        guard let session, session.isRunning else { return }
        session.stopRunning()
        print("Camera stopped")
    }
    
    private func handleAuthorization() async throws -> Bool {
        var isGranted = false
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined: isGranted = await AVCaptureDevice.requestAccess(for: .video)
        case .restricted: throw CameraServiceError.denied
        case .denied: throw CameraServiceError.denied
        case .authorized: isGranted = true
        @unknown default: fatalError("Unhandled AVCaptureDevice.authorizationStatus")
        }
        return isGranted
    }
    
    
    
    private func setupSession(previewLayer: AVCaptureVideoPreviewLayer) throws {
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        guard let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraServiceError.failedToGetGevice
        }
        self.device = device
        
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        } catch {
            throw CameraServiceError.failedToConfigureCamera(error)
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw CameraServiceError.cannotAddInput
            }
            session.addInput(input)
        } catch {
            throw CameraServiceError.failedToCreateInput(error)
        }
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        
        guard session.canAddOutput(output) else {
            throw CameraServiceError.cannotAddOutput
        }
        session.addOutput(output)
        self.output = output
        
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
        
        self.previewLayer = previewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyRotationAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, change in
            guard let angle = change.newValue else { return }
            Task { await self?.applyRotationAngle(angle) }
        }
        
        session.commitConfiguration()
        
        self.session = session
    }
    
    private func applyRotationAngle(_ angle: CGFloat) {
        if let previewConnection = previewLayer?.connection, previewConnection.isVideoRotationAngleSupported(angle) {
            previewConnection.videoRotationAngle = angle
        }
        if let outputConnection = output?.connection(with: .video), outputConnection.isVideoRotationAngleSupported(angle) {
            outputConnection.videoRotationAngle = angle
        }
    }
    
    enum CameraServiceError: Error {
        case denied
        case failedToGetGevice
        case failedToCreateInput(Error)
        case cannotAddInput
        case cannotAddOutput
        case failedToConfigureCamera(Error)
    }
    
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let w = SendableWrapper(value: sampleBuffer)
        Task {
            callback?(w)
        }
    }
    
    // MARK: -
}
