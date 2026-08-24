import Cocoa
import Metal
import MetalKit

// MARK: - Metal GPU Hyperspace Warp Engine

class MetalWarpView: NSView, ScreensaverContent, MTKViewDelegate {
    var mtkView: MTKView!
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var startTime: CFTimeInterval = 0

    struct Uniforms {
        var time: Float
        var width: Float
        var height: Float
        var speed: Float
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            return
        }
        self.device = metalDevice
        self.commandQueue = metalDevice.makeCommandQueue()

        mtkView = MTKView(frame: bounds, device: metalDevice)
        mtkView.delegate = self
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.preferredFramesPerSecond = 60
        mtkView.autoresizingMask = [.width, .height]
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        addSubview(mtkView)

        setupPipeline()
        startTime = CACurrentMediaTime()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        mtkView.frame = bounds
    }

    func setupPipeline() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        struct Uniforms {
            float time;
            float width;
            float height;
            float speed;
        };

        vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1.0, -1.0),
                float2( 1.0, -1.0),
                float2(-1.0,  1.0),
                float2( 1.0,  1.0)
            };
            float2 uvs[4] = {
                float2(0.0, 1.0),
                float2(1.0, 1.0),
                float2(0.0, 0.0),
                float2(1.0, 0.0)
            };

            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.uv = uvs[vertexID];
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
            float2 resolution = float2(u.width, u.height);
            float2 p = (in.position.xy - 0.5 * resolution) / min(resolution.x, resolution.y);
            
            float t = u.time * u.speed * 0.8;
            float r = length(p);
            float angle = atan2(p.y, p.x);
            
            // Warp tunnel coordinates
            float2 uv = float2(1.0 / (r + 0.02) + t * 2.0, angle / 3.14159265);
            
            // Multi-layered star streaks
            float acc = 0.0;
            for (float i = 1.0; i <= 4.0; i += 1.0) {
                float2 st = uv * (i * 3.0);
                float f = fract(st.x) - 0.5;
                float g = fract(st.y * 6.0) - 0.5;
                float d = length(float2(f * 0.15, g));
                float brightness = max(0.0, 1.0 - d * 18.0) * min(1.0, r * 1.5);
                acc += brightness / i;
            }
            
            // Cosmic neon coloring (Cyan core into electric Purple / Deep Blue)
            float3 col = float3(0.0);
            col += float3(0.1, 0.5, 1.0) * acc * 1.8;
            col += float3(0.6, 0.1, 0.9) * (sin(angle * 3.0 + t) * 0.2 + 0.3) * acc;
            col += float3(0.0, 0.9, 0.8) * exp(-r * 6.0) * 1.2; // Central warp bloom
            
            return float4(col, 1.0);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunc = library.makeFunction(name: "vertexShader")
            let fragmentFunc = library.makeFunction(name: "fragmentShader")

            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.vertexFunction = vertexFunc
            pipelineDesc.fragmentFunction = fragmentFunc
            pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("Failed to create Metal pipeline state: \\(error)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }

        let elapsed = Float(CACurrentMediaTime() - startTime)
        var uniforms = Uniforms(
            time: elapsed,
            width: Float(bounds.width),
            height: Float(bounds.height),
            speed: 1.0
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func startPlayback() {
        startTime = CACurrentMediaTime()
        mtkView?.isPaused = false
    }

    func stopPlayback() {
        mtkView?.isPaused = true
    }
}
