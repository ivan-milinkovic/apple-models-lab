//
//  VisionView.swift
//  ModelLab
//
//  Created by Ivan Milinkovic on 27. 6. 2026.
//

import SwiftUI
@preconcurrency import AVFoundation

struct VisionView: View {
    
    @State var viewModel = VisionViewModel()
    
    var body: some View {
        VStack {
            if let captureSession = viewModel.session {
                camera(session: captureSession)
                    .ignoresSafeArea()
            } else {
                ProgressView()
            }
            if let message = viewModel.message {
                Text(message)
            }
        }
        .task {
            await viewModel.setup()
        }
        .onAppear {
            Task { await viewModel.start() }
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
        .toolbar {
            ToolbarItem(placement: toolbarPlacement()) {
                Picker("", selection: $viewModel.detectionType) {
                    Text("Face").tag(VisionViewModel.Mode.face)
                    Text("Pose").tag(VisionViewModel.Mode.pose)
                    Text("Eyes").tag(VisionViewModel.Mode.eyes)
                    Text("Mustache").tag(VisionViewModel.Mode.mustaches)
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    private func toolbarPlacement() -> ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }
    
    private func camera(session: AVCaptureSession) -> some View {
        CameraPreview(session: session, pointMapper: viewModel.pointMapper)
            .overlay {
                switch viewModel.detectionType {
                case .face: facePoints
                case .pose: bodyPosePoints
                case .eyes: eyeLines
                case .mustaches: mustaches
                }
            }
    }
    
    @ViewBuilder private var bodyPosePoints: some View {
        Canvas { ctx, size in
            for (i, group) in viewModel.bodyPoseGroups.enumerated() {
                let color = colors[i % colors.count]
                for point in group.points {
                    let p = mapPoint(point.coords, containerSize: size)
                    let r = CGRect(x: p.x-5, y: p.y-5, width: 10, height: 10)
                    ctx.fill(Path(ellipseIn: r), with: .color(color))
                    let r2 = CGRect(x: p.x-5, y: p.y-10, width: 200, height: 50)
                    ctx.draw(Text(point.name), in: r2)
                }
            }
        }
    }
    
    @ViewBuilder private var facePoints: some View {
        let dotSize = 7.0
        Canvas { ctx, size in
            for (i, group) in viewModel.faceGroups.enumerated() {
                let color = colors[i % colors.count]
                for point in group.points {
                    let p = mapPoint(point.coords, containerSize: size)
                    let r = CGRect(x: p.x-dotSize/2, y: p.y-dotSize/2, width: dotSize, height: dotSize)
                    ctx.fill(Path(ellipseIn: r), with: .color(color))
                    let r2 = CGRect(x: p.x-5, y: p.y-10, width: 200, height: 50)
                    ctx.draw(Text(point.name), in: r2)
                }
            }
        }
    }
    
    @ViewBuilder private var pointsHistory: some View {
        Canvas { ctx, size in
            let dotSize = 4.0
            let color = colors[1]
            for (i, point) in viewModel.eyeHistory.enumerated() {
                let opacity = 0.5 * (1 - Double(i) / Double(viewModel.eyeHistory.count))
                let p = mapPoint(point, containerSize: size)
                let r = CGRect(x: p.x-dotSize/2, y: p.y-dotSize/2, width: dotSize, height: dotSize)
                ctx.fill(Path(ellipseIn: r), with: .color(color.opacity(opacity)))
            }
        }
    }
    
    @ViewBuilder private var eyeLines: some View {
        Canvas { ctx, size in
            let color = colors[1]
            
            let eyePoint = mapPoint(viewModel.eyePoint, containerSize: size)
            let r = CGRect(origin: eyePoint,
                           size: CGSize(width: 8, height: 8))
            ctx.fill(Path(ellipseIn: r), with: .color(color))
                     
            var path = Path()
            path.move(to: eyePoint)
            for (_, point) in viewModel.eyeHistory.enumerated() {
                if point.x == -1 { break }
                let p = mapPoint(point, containerSize: size)
                path.addLine(to: p)
            }
            ctx.stroke(path, with: .color(color), style: .init(lineWidth: 8))
        }
    }
    
    private let colors: [Color] = [.orange, .blue, .purple, .yellow]
    
    @ViewBuilder private var mustaches: some View {
        ForEach(viewModel.mustaches) { m in
            mustache(m)
        }
    }
    
    @ViewBuilder private func mustache(_ mustache: VisionViewModel.MustachePoints) -> some View {
        Canvas { ctx, size in
            
            var lipsL = mapPoint(mustache.lipsL, containerSize: size)
            var lipsR = mapPoint(mustache.lipsR, containerSize: size)
            let lipsTop = mapPoint(mustache.lipsTop, containerSize: size)
            let noseBot = mapPoint(mustache.noseBot, containerSize: size)
            let size = mapSize(mustache.size, containerSize: size)
            
            // Strech a bit
            lipsL = lipsL.applying(CGAffineTransform.init(translationX: -size.width*0.3, y: 0))
            lipsR = lipsR.applying(CGAffineTransform.init(translationX:  size.width*0.3, y: 0))
            
            // simple test
            // var path = Path()
            // path.move(to: lipsL)
            // path.addLine(to: noseBot)
            // path.addLine(to: mapPoint(mustache.lipsR, size))
            // path.addLine(to: mapPoint(mustache.lipsTop, size))
            // path.closeSubpath()
 
            var path = Path()
            
            path.move(to: lipsL)
            
            let xt_more = size.width*0.3
            let xt_less = size.width*0.2
            let yt_more = size.height*0.4
            let yt_less = size.height*0.1
            
            // Left to nose
            path.addCurve(
                to: noseBot,
                control1:   lipsL.applying(CGAffineTransform(translationX:  xt_more, y: -yt_less)),
                control2: noseBot.applying(CGAffineTransform(translationX: -xt_more, y: -yt_more))
            )
            
            // Nose to right
            path.addCurve(
                to: lipsR,
                control1: noseBot.applying(CGAffineTransform(translationX:  xt_more, y: -yt_more)),
                control2:   lipsR.applying(CGAffineTransform(translationX: -xt_less, y: -yt_less))
            )
            
            // Right to top lip
            path.addCurve(
                to: lipsTop,
                control1:   lipsR.applying(CGAffineTransform(translationX: -xt_more, y: yt_more)),
                control2: lipsTop.applying(CGAffineTransform(translationX:  xt_more, y: yt_more))
            )
            
            // Top lip to left
            path.addCurve(
                to: lipsL,
                control1: lipsTop.applying(CGAffineTransform(translationX: -xt_more, y: yt_more)),
                control2:   lipsL.applying(CGAffineTransform(translationX:  xt_less, y: yt_more))
            )
            
            ctx.fill(path, with: .color(.black))
        }
    }
    
    /// Maps a normalized Vision point (origin bottom-left, y-up, relative to the upright
    /// orientation-corrected image) directly onto the container view, replicating the
    /// same aspect-fill scale + crop that the video preview itself uses. This uses the
    /// real pixel buffer dimensions (viewModel.uprightImageSize) instead of going through
    /// AVCaptureConnection APIs, so it doesn't depend on the connection's rotation/gravity
    /// state being configured a particular way.
    private func mapPoint(_ p: CGPoint, containerSize size: CGSize) -> CGPoint {
        let (scale, offset) = aspectFillTransform(containerSize: size)
        guard let scale else { return .zero }
        let imageSize = viewModel.uprightImageSize
        // vision origin is bottom left, convert to top-left-origin image pixel coords
        let imageX = p.x * imageSize.width
        let imageY = (1 - p.y) * imageSize.height
        return CGPoint(x: imageX * scale + offset.x, y: imageY * scale + offset.y)
    }
    
    private func mapSize(_ s: CGSize, containerSize size: CGSize) -> CGSize {
        let (scale, _) = aspectFillTransform(containerSize: size)
        guard let scale else { return .zero }
        let imageSize = viewModel.uprightImageSize
        return CGSize(width: s.width * imageSize.width * scale,
                      height: s.height * imageSize.height * scale)
    }
    
    /// Returns the uniform scale factor and centering offset that resizeAspectFill applies
    /// when fitting `viewModel.uprightImageSize` into `containerSize`.
    private func aspectFillTransform(containerSize size: CGSize) -> (scale: CGFloat?, offset: CGPoint) {
        let imageSize = viewModel.uprightImageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return (nil, .zero) }
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offset = CGPoint(x: (size.width - scaledWidth) / 2, y: (size.height - scaledHeight) / 2)
        return (scale, offset)
    }
}

#Preview {
    VisionView()
}
