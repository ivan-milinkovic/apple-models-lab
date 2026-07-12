//
//  VisionViewModel.swift
//  ModelLab
//
//  Created by Ivan Milinkovic on 29. 6. 2026.
//

import Foundation
import Observation
import Vision
@preconcurrency import AVFoundation
import CoreVideo

@Observable @MainActor final class VisionViewModel {
    @ObservationIgnored let cameraService = CameraService()
    @ObservationIgnored let previewLayer = AVCaptureVideoPreviewLayer()
    @ObservationIgnored var detectionRequest: VNImageBasedRequest?
    var isReady = false
    var message: String?
    var detectionType: Mode = .mustaches
    var uprightImageSize: CGSize = .zero
    
    var bodyPoseGroups: [DetectionGroup] = []
    var faceGroups: [DetectionGroup] = []
    var mustaches = [MustachePoints]()
    
    var eyePoint: CGPoint = .zero
    var eyeHistory: [CGPoint] = .init(repeating: .zero, count: 64)
    let eyesHistoryDeltaTime: TimeInterval = 0.033
    var eyesLastHistoryDate: Date = Date()
    
    // MARK: - Model
    enum Mode: CaseIterable {
        case face, pose, eyes, mustaches
    }
    
    struct MustachePoints: Identifiable {
        var id: UUID
        var lipsL: CGPoint = .zero
        var lipsR: CGPoint = .zero
        var lipsTop: CGPoint = .zero
        var noseBot: CGPoint = .zero
        var size: CGSize = .zero
    }
    
    struct DetectionGroup: Identifiable {
        let id = UUID()
        let points: [DetectionPoint]
    }
    
    struct DetectionPoint: Identifiable {
        let id = UUID()
        let name: String
        let coords: CGPoint
    }
    
    // MARK: -
    
    func setup() async {
        do {
            try await cameraService.setup(previewLayer: SendableWrapper(value: previewLayer))
            isReady = true
            await cameraService.setCallback { buffer in
                Task { @Sendable in
                    await MainActor.run {
                        self.handleBuffer(buffer)
                    }
                }
            }
            await cameraService.start()
        } catch {
            message = error.localizedDescription
        }
    }
    
    func handleBuffer(_ buffer: SendableWrapper<CMSampleBuffer>) {
        guard detectionRequest == nil else {
            return
        }
        
        updateUprightImageSize(from: buffer.value)
        
        detectionRequest = makeRequest()
        defer { detectionRequest = nil}
        do {
            // The video data output connection now delivers an already-upright, already-mirrored
            // buffer (see CameraService), so Vision doesn't need any rotation/mirror hint.
            let imageHandler = VNImageRequestHandler(cmSampleBuffer: buffer.value, orientation: .up)
            try imageHandler.perform([detectionRequest!])
            guard let observations = detectionRequest?.results else { return }
            try handle(observations: observations)
        } catch {
            message = error.localizedDescription
        }
    }
    
    /// Reads the raw pixel buffer's dimensions, which the video data output connection
    /// already delivers upright and orientation-corrected (see CameraService), so no
    /// manual width/height swapping is needed here anymore.
    private func updateUprightImageSize(from sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        uprightImageSize = CGSize(width: width, height: height)
    }
    
    private func makeRequest() -> VNImageBasedRequest {
        switch detectionType {
        case .pose:
            VNDetectHumanBodyPoseRequest()
        case .face, .eyes, .mustaches:
            VNDetectFaceLandmarksRequest()
        }
    }
    
    private func handle(observations: [VNObservation]) throws {
        switch detectionType {
        case .pose:
            try processBodyPose(observations as! [VNHumanBodyPoseObservation])
        case .face:
            processFaceLandmarks(observations as! [VNFaceObservation])
        case .eyes:
            processEyesLandmarks(observations as! [VNFaceObservation])
        case .mustaches:
            processFaceLandmarksForMustache(observations as! [VNFaceObservation])
        }
    }
    
    func processBodyPose(_ observations: [VNHumanBodyPoseObservation]) throws {
        bodyPoseGroups = try observations
            .filter { $0.confidence > 0.4 }
            .map {
                let dict = try $0.recognizedPoints(.all)
                let points = dict.map { (k,v) in DetectionPoint(name: k.rawValue.rawValue, coords: v.location) }
                return DetectionGroup(points: points)
            }
    }
    
    func processFaceLandmarks(_ observations: [VNFaceObservation]) {
        faceGroups = observations.compactMap { face in
            guard let landmarks = face.landmarks,
                  let allPoints = landmarks.allPoints else { return nil }
            let box = face.boundingBox
            let points = allPoints.normalizedPoints.map { pt in
                let imageX = box.minX + pt.x * box.width
                let imageY = box.minY + pt.y * box.height
                return DetectionPoint(name: "", coords: CGPoint(x: imageX, y: imageY))
            }
            return DetectionGroup(points: points)
        }
    }
    
    func processFaceLandmarksForMustache(_ observations: [VNFaceObservation]) {
        mustaches = observations.compactMap { face in
            guard let landmarks = face.landmarks,
                  let lips = landmarks.outerLips,
                  let nose = landmarks.nose
            else { return nil}
            
            let lipsPoints = lips.normalizedPoints
            let nosePoints = nose.normalizedPoints
            
            guard let lipsL = lipsPoints.min(by: { $0.x < $1.x }),
                  let lipsR = lipsPoints.max(by: { $0.x < $1.x }),
                  var lipsTop = lipsPoints.max(by: { $0.y < $1.y }),
                  var noseBot = nosePoints.min(by: { $0.y < $1.y }) // it's upside down, starts from the bottom
            else { return nil }
            
            // find centroids to adjust x coordinate
            // fixes point fighting due to symmetry
            lipsTop.x = centroid(of: lipsPoints).x
            noseBot.x = centroid(of: nosePoints).x
            
            let lipsL2 = mapPoint(lipsL, face.boundingBox)
            let lipsR2 = mapPoint(lipsR, face.boundingBox)
            let lipsTop2 = mapPoint(lipsTop, face.boundingBox)
            let noseBot2 = mapPoint(noseBot, face.boundingBox)
            let size = CGSize(width: abs(lipsR2.x - lipsL2.x),
                              height: abs(noseBot2.y - lipsTop2.y))
            
            return MustachePoints(
                id: face.uuid,
                lipsL: lipsL2,
                lipsR: lipsR2,
                lipsTop: lipsTop2,
                noseBot: noseBot2,
                size: size
            )
        }
    }
    
    func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { acc, point in
            CGPoint(x: acc.x + point.x,
                    y: acc.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count),
                       y: sum.y / CGFloat(points.count))
    }
    
    func mapPoint(_ p: CGPoint, _ bbox: CGRect) -> CGPoint {
        CGPoint(x: bbox.minX + p.x * bbox.width,
                y: bbox.minY + p.y * bbox.height)
    }
    
    func processEyesLandmarks(_ observations: [VNFaceObservation]) {
        guard let face = observations.first(where: { $0.landmarks?.leftEye != nil }),
              let leftEye: VNFaceLandmarkRegion2D = face.landmarks?.leftEye else { return }
        let points = leftEye.normalizedPoints
        guard !points.isEmpty else { return }
        let bbox = face.boundingBox
        let centroid = points.reduce(CGPoint.zero) { acc, point in
            CGPoint(x: acc.x + point.x,
                    y: acc.y + point.y)
        }
        let normalizedCentroid = CGPoint(
            x: centroid.x / CGFloat(points.count),
            y: centroid.y / CGFloat(points.count)
        )
        let leftEyeCentroid = CGPoint(
            x: bbox.minX + normalizedCentroid.x * bbox.width,
            y: bbox.minY + normalizedCentroid.y * bbox.height
        )
        eyePoint = leftEyeCentroid
        
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(eyesLastHistoryDate)
        guard timeSinceLast >= eyesHistoryDeltaTime else { return }
        
        let dx = eyeHistory[0].x - leftEyeCentroid.x
        let dy = eyeHistory[0].y - leftEyeCentroid.y
        let radialDist = dx*dx + dy*dy
        let nds = 0.025 // normalized coord delta distance threshold
        guard radialDist >= 2*nds*nds else { return }
        
        for i in 0..<eyeHistory.count-1 {
            eyeHistory[i+1] = eyeHistory[i]
        }
        eyeHistory[0] = leftEyeCentroid
        eyesLastHistoryDate = Date()
        
    }
    
    func start() async {
        await cameraService.start()
    }
    
    func stop() async {
        await cameraService.stop()
    }
    
    func switchCamera() {
        Task {
            do {
                try await cameraService.switchCamera()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
