import AppKit
import Foundation
import MetalKit
import QuartzCore
import SwiftUI

enum OrbGPU {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    static let library: MTLLibrary? = {
        guard let device else { return nil }
        do {
            return try device.makeLibrary(source: orbMetalSource, options: nil)
        } catch {
            fputs("LiquidOrb shader: \(error)\n", stderr)
            return nil
        }
    }()

    static func warmup() {
        _ = library
    }
}

func warmLiquidOrb() {
    OrbGPU.warmup()
}

private let orbIdleUniformSeed: [Float] = [
    1, 1, 0, 0.31360000371932983, 0.7200000286102295, 0.5335999727249146, 2.1619999408721924, 0.30660000443458557,
    2.5739998817443848, 0.18000000715255737, 0.20000000298023224, 0.3400000035762787, 0.2800000011920929, 0.23999999463558197, 0.8191999793052673, 21,
    0.004999999888241291, 0, 0, 1, 0.6200000047683716, 0.012000000104308128, 2, 0.41999998688697815,
    0.7699999809265137, 0.23000000417232513, 65, 0, 0, 1, 0.2199999988079071, 0.25,
    0.7200000286102295, 5, 0.41999998688697815, 1.25, 0.550000011920929, 0.30000001192092896, 1.2000000476837158, 0.699999988079071,
    0.04313725605607033, 0.0117647061124444, 0.062745101749897, 1, 0.16862745583057404, 0.09019608050584793, 0.2823529541492462, 1,
    0.3490196168422699, 0.1882352977991104, 0.47058823704719543, 1, 0.6078431606292725, 0.47058823704719543, 0.658823549747467, 1,
    0.7372549176216125, 0.6509804129600525, 0.7607843279838562, 1, 0.9882352948188782, 0.9607843160629272, 1, 1,
    0.7607843279838562, 0.34117648005485535, 1, 1, 0.42352941632270813, 0.1764705926179886, 1, 1,
    0.9725490212440491, 0.9019607901573181, 1, 1, 0.8313725590705872, 0.7176470756530762, 1, 1,
    0.0117647061124444, 0, 0.0235294122248888, 1, 0.3490196168422699, 0.19607843458652496, 0.45098039507865906, 1,
    0.9686274528503418, 0.9843137264251709, 1, 1, 0.9372549057006836, 0.9647058844566345, 0.9921568632125854, 1,
    0.8784313797950745, 0.9333333373069763, 0.9764705896377563, 1, 0.8313725590705872, 0.9019607901573181, 0.9686274528503418, 1,
    0.7333333492279053, 0.8352941274642944, 0.9529411792755127, 1, 0.6509804129600525, 0.7803921699523926, 0.9411764740943909, 1,
    0.529411792755127, 0.6901960968971252, 0.9215686321258545, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
]

private let orbThinkingUniformSeed: [Float] = [
    1, 1, 0, 1.1200000047683716, 0.7200000286102295, 0.5799999833106995, 4.699999809265137, 0.7300000190734863,
    3.299999952316284, 0.18000000715255737, 0.20000000298023224, 0.3400000035762787, 0.2800000011920929, 0.23999999463558197, 1.2799999713897705, 21,
    0.004999999888241291, 0, 0, 1, 0.6200000047683716, 0.03999999910593033, 2, 0.41999998688697815,
    0.7699999809265137, 0.23000000417232513, 65, 0, 0, 1, 0.2199999988079071, 0.25,
    0.7200000286102295, 5, 0.41999998688697815, 1.25, 0.550000011920929, 0.30000001192092896, 1.2000000476837158, 0.699999988079071,
    0.062745101749897, 0, 0.08627451211214066, 1, 0.29019609093666077, 0.054901961237192154, 0.5607843399047852, 1,
    0.6470588445663452, 0.18039216101169586, 1, 1, 0.9450980424880981, 0.6549019813537598, 1, 1,
    1, 0.8392156958580017, 1, 1, 0.9882352948188782, 0.9607843160629272, 1, 1,
    0.7607843279838562, 0.34117648005485535, 1, 1, 0.42352941632270813, 0.1764705926179886, 1, 1,
    0.9725490212440491, 0.9019607901573181, 1, 1, 0.8313725590705872, 0.7176470756530762, 1, 1,
    0.0117647061124444, 0, 0.0235294122248888, 1, 0.6470588445663452, 0.18039216101169586, 1, 1,
    0.9686274528503418, 0.9843137264251709, 1, 1, 0.9372549057006836, 0.9647058844566345, 0.9921568632125854, 1,
    0.8784313797950745, 0.9333333373069763, 0.9764705896377563, 1, 0.8313725590705872, 0.9019607901573181, 0.9686274528503418, 1,
    0.7333333492279053, 0.8352941274642944, 0.9529411792755127, 1, 0.6509804129600525, 0.7803921699523926, 0.9411764740943909, 1,
    0.529411792755127, 0.6901960968971252, 0.9215686321258545, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
]

private let orbActivationDuration: CFTimeInterval = 0.22
private let orbSettleDuration: CFTimeInterval = 0.65
private let orbRibbonStyleIndex: Float = 24
private let orbRibbonInstanceCount = 221184

public struct LiquidOrbAudio: Sendable {
    public var low: Float
    public var mid: Float
    public var high: Float
    public var all: Float
    public init(low: Float = 0, mid: Float = 0, high: Float = 0, all: Float = 0) {
        self.low = low; self.mid = mid; self.high = high; self.all = all
    }
}

private func applyOrbAudio(_ values: inout [Float], _ bands: LiquidOrbAudio) {
    let strengths: [Int: Float] = [9: 0.8, 10: 0.65, 11: 0.65, 14: 0.75, 19: 1, 21: 0.7]
    guard let strength = strengths[Int(values[15].rounded())] else { return }
    func level(_ value: Float) -> Float { value.isFinite ? max(0, min(1, value)) * strength : 0 }
    if level(bands.all) > 0 { values[3] = min(max(5, values[3]), values[3] * (1 + 0.7 * level(bands.all)) + 0 * level(bands.all)) }
    if level(bands.mid) > 0 { values[6] = min(max(7, values[6]), values[6] * (1 + 0 * level(bands.mid)) + 0.85 * level(bands.mid)) }
    if level(bands.low) > 0 { values[21] = min(max(1, values[21]), values[21] * (1 + 0 * level(bands.low)) + 0.075 * level(bands.low)) }
    if level(bands.high) > 0 { values[10] = min(max(2, values[10]), values[10] * (1 + 0 * level(bands.high)) + 0.16 * level(bands.high)) }
    if level(bands.all) > 0 { values[14] = min(max(4, values[14]), values[14] * (1 + 0.12 * level(bands.all)) + 0 * level(bands.all)) }
}

public enum LiquidOrbState: Sendable {
    case idle
    case thinking
}

private func orbUniformSeed(for state: LiquidOrbState) -> [Float] {
    switch state {
    case .idle: orbIdleUniformSeed
    case .thinking: orbThinkingUniformSeed
    }
}

private func orbSrgbToLinear(_ value: Float) -> Float {
    value <= 0.04045
        ? value / 12.92
        : Float(pow(Double((value + 0.055) / 1.055), 2.4))
}

private func orbLinearToSrgb(_ value: Float) -> Float {
    value <= 0.0031308
        ? value * 12.92
        : 1.055 * Float(pow(Double(value), 1.0 / 2.4)) - 0.055
}

private func orbMixSrgb(_ from: Float, _ to: Float, _ progress: Float) -> Float {
    orbLinearToSrgb(
        orbSrgbToLinear(from) + (orbSrgbToLinear(to) - orbSrgbToLinear(from)) * progress
    )
}

private enum LiquidOrbError: Error {
    case metalUnavailable
    case shaderFunctionMissing(String)
    case commandQueueUnavailable
}

private final class PassthroughMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class LiquidOrbRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let ribbonPipeline: MTLRenderPipelineState
    private let ribbonCompositePipeline: MTLRenderPipelineState
    private var ribbonTexture: MTLTexture?
    private var lastFrameAt = CACurrentMediaTime()
    private var motionPhase: CFTimeInterval = 0
    private var audio = LiquidOrbAudio()

    func setAudio(_ audio: LiquidOrbAudio) {
        stateLock.lock()
        self.audio = audio
        stateLock.unlock()
    }
    private let stateLock = NSLock()
    private var currentState: LiquidOrbState
    private var transitionTargetState: LiquidOrbState
    private var fromUniforms: [Float]
    private var targetUniforms: [Float]
    private var displayedUniforms: [Float]
    private var transitionStartedAt = CACurrentMediaTime()
    private var activeTransitionDuration: CFTimeInterval = 0

    init(view: MTKView, state: LiquidOrbState) throws {
        let initialUniforms = orbUniformSeed(for: state)
        currentState = state
        transitionTargetState = state
        fromUniforms = initialUniforms
        targetUniforms = initialUniforms
        displayedUniforms = initialUniforms

        guard let device = OrbGPU.device else {
            throw LiquidOrbError.metalUnavailable
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let library = OrbGPU.library else {
            throw LiquidOrbError.shaderFunctionMissing("orb")
        }
        guard let vertex = library.makeFunction(name: "vs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("vs_main")
        }
        guard let fragment = library.makeFunction(name: "fs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("fs_main")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        guard let ribbonVertex = library.makeFunction(name: "ribbon_vs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("ribbon_vs_main")
        }
        guard let ribbonFragment = library.makeFunction(name: "ribbon_fs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("ribbon_fs_main")
        }
        let ribbonDescriptor = MTLRenderPipelineDescriptor()
        ribbonDescriptor.vertexFunction = ribbonVertex
        ribbonDescriptor.fragmentFunction = ribbonFragment
        ribbonDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        ribbonDescriptor.colorAttachments[0].isBlendingEnabled = true
        ribbonDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        ribbonDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        ribbonDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        ribbonDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        ribbonPipeline = try device.makeRenderPipelineState(descriptor: ribbonDescriptor)
        guard let ribbonCompositeFragment = library.makeFunction(name: "ribbon_composite_fs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("ribbon_composite_fs_main")
        }
        let ribbonCompositeDescriptor = MTLRenderPipelineDescriptor()
        ribbonCompositeDescriptor.vertexFunction = vertex
        ribbonCompositeDescriptor.fragmentFunction = ribbonCompositeFragment
        ribbonCompositeDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        ribbonCompositeDescriptor.colorAttachments[0].isBlendingEnabled = true
        ribbonCompositeDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        ribbonCompositeDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        ribbonCompositeDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        ribbonCompositeDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        ribbonCompositePipeline = try device.makeRenderPipelineState(descriptor: ribbonCompositeDescriptor)
        guard let queue = device.makeCommandQueue() else {
            throw LiquidOrbError.commandQueueUnavailable
        }
        commandQueue = queue
        super.init()
    }

    func setState(_ state: LiquidOrbState) {
        let now = CACurrentMediaTime()
        stateLock.lock()
        defer { stateLock.unlock() }
        guard state != currentState else { return }

        let nextUniforms = orbUniformSeed(for: state)
        fromUniforms = sampleTransition(at: now)
        targetUniforms = nextUniforms
        transitionTargetState = state
        transitionStartedAt = now
        activeTransitionDuration = state == .thinking ? orbActivationDuration : orbSettleDuration
        currentState = state
    }

    private func sampleTransition(at now: CFTimeInterval) -> [Float] {
        let rawProgress = activeTransitionDuration == 0
            ? 1
            : min(1, max(0, (now - transitionStartedAt) / activeTransitionDuration))
        let easedProgress = transitionTargetState == .thinking
            ? 1 - pow(1 - rawProgress, 3)
            : rawProgress * rawProgress * (3 - 2 * rawProgress)
        let progress = Float(easedProgress)

        for index in 3..<displayedUniforms.count {
            let isColorComponent = index >= 40 && (index - 40) % 4 < 3
            displayedUniforms[index] = isColorComponent
                ? orbMixSrgb(fromUniforms[index], targetUniforms[index], progress)
                : fromUniforms[index] + (targetUniforms[index] - fromUniforms[index]) * progress
        }
        return displayedUniforms
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        ribbonTexture = nil
    }

    private func ensureRibbonTexture(for view: MTKView) -> MTLTexture? {
        let width = max(1, Int(view.drawableSize.width))
        let height = max(1, Int(view.drawableSize.height))
        if let ribbonTexture, ribbonTexture.width == width, ribbonTexture.height == height {
            return ribbonTexture
        }
        guard let device = view.device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: view.colorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        ribbonTexture = device.makeTexture(descriptor: descriptor)
        return ribbonTexture
    }

    func draw(in view: MTKView) {
        guard
            view.drawableSize.width > 0,
            view.drawableSize.height > 0,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let now = CACurrentMediaTime()
        stateLock.lock()
        var uniforms = sampleTransition(at: now)
        applyOrbAudio(&uniforms, audio)
        stateLock.unlock()
        let frameDelta = min(0.1, max(0, now - lastFrameAt))
        lastFrameAt = now
        motionPhase += frameDelta * CFTimeInterval(max(uniforms[3], 0))
        uniforms[0] = Float(view.drawableSize.width)
        uniforms[1] = Float(view.drawableSize.height)
        uniforms[2] = Float(motionPhase / CFTimeInterval(max(uniforms[3], 0.001)))
        let isParticleRibbon = round(uniforms[15]) == orbRibbonStyleIndex
        if isParticleRibbon {
            guard let ribbonTexture = ensureRibbonTexture(for: view) else { return }
            let ribbonPass = MTLRenderPassDescriptor()
            ribbonPass.colorAttachments[0].texture = ribbonTexture
            ribbonPass.colorAttachments[0].loadAction = .clear
            ribbonPass.colorAttachments[0].storeAction = .store
            ribbonPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let ribbonEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: ribbonPass) else { return }
            ribbonEncoder.setRenderPipelineState(ribbonPipeline)
            uniforms.withUnsafeBytes { bytes in
                ribbonEncoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 0)
                ribbonEncoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
            }
            ribbonEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: orbRibbonInstanceCount)
            ribbonEncoder.endEncoding()
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(isParticleRibbon ? ribbonCompositePipeline : pipeline)
        uniforms.withUnsafeBytes { bytes in
            encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        if isParticleRibbon {
            encoder.setFragmentTexture(ribbonTexture, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private final class LiquidOrbCoordinator {
    private var renderer: LiquidOrbRenderer?

    func setAudio(_ audio: LiquidOrbAudio) { renderer?.setAudio(audio) }

    func makeView(state: LiquidOrbState) -> MTKView {
        let view = PassthroughMTKView(frame: .zero, device: OrbGPU.device)
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        do {
            let renderer = try LiquidOrbRenderer(view: view, state: state)
            self.renderer = renderer
            view.delegate = renderer
        } catch {
            fputs("LiquidOrb: \(error)\n", stderr)
        }
        return view
    }

    func setState(_ state: LiquidOrbState) {
        renderer?.setState(state)
    }
}

private struct LiquidOrbSurface: NSViewRepresentable {
    let state: LiquidOrbState
    var audio = LiquidOrbAudio()
    var active = true

    func makeCoordinator() -> LiquidOrbCoordinator { LiquidOrbCoordinator() }
    func makeNSView(context: Context) -> MTKView { context.coordinator.makeView(state: state) }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.setState(state)
        context.coordinator.setAudio(audio)
        view.isPaused = !active
    }
}

public struct LiquidOrbView: View {
    private let state: LiquidOrbState
    private var audio = LiquidOrbAudio()
    private var active: Bool

    public init(state: LiquidOrbState = .idle, audio: LiquidOrbAudio = LiquidOrbAudio(), active: Bool = true) {
        self.state = state
        self.audio = audio
        self.active = active
    }

    public var body: some View {
        LiquidOrbSurface(state: state, audio: audio, active: active)
    }
}
