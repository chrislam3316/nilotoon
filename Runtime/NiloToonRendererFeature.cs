using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

// Unity 6 / URP 17 Render Graph. Add once to each renderer used by character cameras.
public sealed class NiloToonRendererFeature : ScriptableRendererFeature
{
    [SerializeField] LayerMask characterLayers = ~0;
    [Tooltip("Assign NiloToonPostProcess.shader to retain the optional post effect in builds.")]
    [SerializeField] Shader postProcessShader;

    static readonly int HairTexture = Shader.PropertyToID("_NiloHairDepthTexture");
    static readonly int HairAvailable = Shader.PropertyToID("_NiloHairDepthAvailable");
    static readonly int StyleEnabled = Shader.PropertyToID("_NiloGlobalStyleEnabled");
    static readonly int Style = Shader.PropertyToID("_NiloGlobalStyle");
    static readonly int Tint = Shader.PropertyToID("_NiloGlobalTint");
    static readonly int ShadowTint = Shader.PropertyToID("_NiloGlobalShadowTint");
    static readonly int BlitTexture = Shader.PropertyToID("_BlitTexture");
    static readonly int BlitScaleBias = Shader.PropertyToID("_BlitScaleBias");
    static readonly int MaskTexture = Shader.PropertyToID("_NiloCharacterMaskTexture");
    static readonly int BloomTexture = Shader.PropertyToID("_NiloBloomTexture");
    static readonly int BloomSettings = Shader.PropertyToID("_NiloBloomSettings");
    static readonly int PostSettings = Shader.PropertyToID("_NiloPostSettings");
    static readonly int BlurDirection = Shader.PropertyToID("_NiloBlurDirection");

    Material postMaterial;
    HairPass hairPass;
    OutlinePass outlinePass;
    EyePass eyePass;
    PostPass postPass;

    public override void Create()
    {
        CoreUtils.Destroy(postMaterial);
        postMaterial = postProcessShader != null ? CoreUtils.CreateEngineMaterial(postProcessShader) : null;
        hairPass = new HairPass(characterLayers);
        outlinePass = new OutlinePass(characterLayers);
        eyePass = new EyePass(characterLayers);
        postPass = new PostPass(characterLayers, postMaterial);
        RenderPipelineManager.beginCameraRendering -= ResetCameraGlobals;
        RenderPipelineManager.beginCameraRendering += ResetCameraGlobals;
    }

    static void ResetCameraGlobals(ScriptableRenderContext context, Camera camera)
    {
        // A camera using another renderer must never consume the preceding camera's textures/style.
        var cmd = CommandBufferPool.Get("Reset Nilo Toon camera state");
        cmd.SetGlobalFloat(HairAvailable, 0f);
        cmd.SetGlobalFloat(StyleEnabled, 0f);
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var cameraType = renderingData.cameraData.cameraType;
        if (cameraType != CameraType.Game && cameraType != CameraType.SceneView)
            return;

        renderer.EnqueuePass(hairPass);
        renderer.EnqueuePass(outlinePass);
        renderer.EnqueuePass(eyePass);
        var volume = VolumeManager.instance.stack.GetComponent<NiloToonVolume>();
        if (postMaterial != null && volume != null && volume.HasPostProcess() &&
            renderingData.cameraData.postProcessEnabled)
            renderer.EnqueuePass(postPass);
    }

    protected override void Dispose(bool disposing)
    {
        RenderPipelineManager.beginCameraRendering -= ResetCameraGlobals;
        CoreUtils.Destroy(postMaterial);
        Shader.SetGlobalFloat(HairAvailable, 0f);
        Shader.SetGlobalFloat(StyleEnabled, 0f);
    }

    static RendererListHandle CreateList(RenderGraph graph, ContextContainer frameData, string tag, int layers)
    {
        var rendering = frameData.Get<UniversalRenderingData>();
        var camera = frameData.Get<UniversalCameraData>();
        var lights = frameData.Get<UniversalLightData>();
        var drawing = RenderingUtils.CreateDrawingSettings(new ShaderTagId(tag), rendering, camera,
            lights, camera.defaultOpaqueSortFlags);
        var filtering = new FilteringSettings(RenderQueueRange.opaque, layers);
        return graph.CreateRendererList(new RendererListParams(rendering.cullResults, drawing, filtering));
    }

    sealed class HairPass : ScriptableRenderPass
    {
        readonly int layers;
        sealed class PassData
        {
            public RendererListHandle renderers;
            public Vector4 style;
            public Color tint, shadowTint;
            public float styleEnabled;
        }

        public HairPass(int layers)
        {
            this.layers = layers;
            renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
            // Force current-camera depth before opaque shading, also used by screen-space rims.
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        public override void RecordRenderGraph(RenderGraph graph, ContextContainer frameData)
        {
            var resources = frameData.Get<UniversalResourceData>();
            var desc = graph.GetTextureDesc(resources.activeColorTexture);
            desc.name = "Nilo hair depth and character ID";
            desc.colorFormat = GraphicsFormat.R32G32_SFloat;
            desc.msaaSamples = MSAASamples.None;
            desc.bindTextureMS = false;
            desc.memoryless = RenderTextureMemoryless.None;
            desc.clearBuffer = true;
            desc.clearColor = Color.clear;
            desc.filterMode = FilterMode.Point;
            var hair = graph.CreateTexture(desc);
            desc.name = "Nilo hair depth attachment";
            desc.depthBufferBits = DepthBits.Depth24;
            var depth = graph.CreateTexture(desc);

            using var builder = graph.AddRasterRenderPass<PassData>("Nilo hair and camera style", out var data);
            data.renderers = CreateList(graph, frameData, "NiloHairDepth", layers);
            var volume = VolumeManager.instance.stack.GetComponent<NiloToonVolume>();
            bool enabled = volume != null && volume.IsActive();
            data.styleEnabled = enabled ? 1f : 0f;
            data.style = enabled ? new Vector4(volume.rimMultiplier.value, volume.shadowMultiplier.value,
                volume.characterSaturation.value, 1f) : Vector4.one;
            data.tint = enabled ? volume.characterTint.value : Color.white;
            data.shadowTint = enabled ? volume.shadowTint.value : Color.white;
            builder.UseRendererList(data.renderers);
            builder.SetRenderAttachment(hair, 0, AccessFlags.Write);
            builder.SetRenderAttachmentDepth(depth, AccessFlags.Write);
            builder.SetGlobalTextureAfterPass(hair, HairTexture);
            builder.AllowGlobalStateModification(true);
            builder.AllowPassCulling(false);
            builder.SetRenderFunc(static (PassData pass, RasterGraphContext context) =>
            {
                context.cmd.SetGlobalFloat(HairAvailable, 1f);
                context.cmd.SetGlobalFloat(StyleEnabled, pass.styleEnabled);
                context.cmd.SetGlobalVector(Style, pass.style);
                context.cmd.SetGlobalColor(Tint, pass.tint);
                context.cmd.SetGlobalColor(ShadowTint, pass.shadowTint);
                context.cmd.DrawRendererList(pass.renderers);
            });
        }
    }

    sealed class OutlinePass : ScriptableRenderPass
    {
        readonly int layers;
        sealed class PassData { public RendererListHandle renderers; }
        public OutlinePass(int layers)
        {
            this.layers = layers;
            renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        }
        public override void RecordRenderGraph(RenderGraph graph, ContextContainer frameData)
        {
            var resources = frameData.Get<UniversalResourceData>();
            using var builder = graph.AddRasterRenderPass<PassData>("Nilo extra outline", out var data);
            data.renderers = CreateList(graph, frameData, "NiloExtraOutline", layers);
            builder.UseRendererList(data.renderers);
            builder.SetRenderAttachment(resources.activeColorTexture, 0, AccessFlags.ReadWrite);
            builder.SetRenderAttachmentDepth(resources.activeDepthTexture, AccessFlags.Read);
            builder.SetRenderFunc(static (PassData pass, RasterGraphContext context) =>
                context.cmd.DrawRendererList(pass.renderers));
        }
    }

    sealed class EyePass : ScriptableRenderPass
    {
        readonly int layers;
        sealed class PassData { public RendererListHandle renderers; }

        public EyePass(int layers)
        {
            this.layers = layers;
            renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        public override void RecordRenderGraph(RenderGraph graph, ContextContainer frameData)
        {
            var resources = frameData.Get<UniversalResourceData>();
            if (!resources.cameraDepthTexture.IsValid())
                return;
            using var builder = graph.AddRasterRenderPass<PassData>("Nilo eyes over own hair", out var data);
            data.renderers = CreateList(graph, frameData, "NiloEyeOverlay", layers);
            builder.UseRendererList(data.renderers);
            builder.UseAllGlobalTextures(true);
            builder.UseTexture(resources.cameraDepthTexture, AccessFlags.Read);
            // The shader checks sampled depth itself; ZTest Always needs no depth attachment.
            builder.SetRenderAttachment(resources.activeColorTexture, 0, AccessFlags.ReadWrite);
            builder.SetRenderFunc(static (PassData pass, RasterGraphContext context) =>
                context.cmd.DrawRendererList(pass.renderers));
        }
    }

    sealed class PostPass : ScriptableRenderPass
    {
        readonly int layers;
        readonly Material material;
        sealed class MaskData { public RendererListHandle renderers; }
        sealed class BlitData
        {
            public TextureHandle source, auxiliary;
            public Material material;
            public MaterialPropertyBlock properties;
            public int passIndex, auxiliaryId;
        }

        public PostPass(int layers, Material material)
        {
            this.layers = layers;
            this.material = material;
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            requiresIntermediateTexture = true;
        }

        public override void RecordRenderGraph(RenderGraph graph, ContextContainer frameData)
        {
            var resources = frameData.Get<UniversalResourceData>();
            var volume = VolumeManager.instance.stack.GetComponent<NiloToonVolume>();
            if (resources.isActiveTargetBackBuffer || material == null || volume == null || !volume.HasPostProcess())
                return;

            TextureHandle source = resources.activeColorTexture;
            TextureHandle bloom = TextureHandle.nullHandle;
            if (volume.HasBloom())
            {
                var maskDesc = graph.GetTextureDesc(resources.activeDepthTexture);
                maskDesc.name = "Nilo visible character bloom mask";
                maskDesc.colorFormat = GraphicsFormat.R8G8B8A8_UNorm;
                maskDesc.bindTextureMS = false;
                maskDesc.memoryless = RenderTextureMemoryless.None;
                maskDesc.clearBuffer = true;
                maskDesc.clearColor = Color.clear;
                var mask = graph.CreateTexture(maskDesc);
                using (var builder = graph.AddRasterRenderPass<MaskData>("Nilo character bloom mask", out var data))
                {
                    data.renderers = CreateList(graph, frameData, "NiloCharacterMask", layers);
                    builder.UseRendererList(data.renderers);
                    builder.SetRenderAttachment(mask, 0, AccessFlags.Write);
                    builder.SetRenderAttachmentDepth(resources.activeDepthTexture, AccessFlags.Read);
                    builder.SetRenderFunc(static (MaskData pass, RasterGraphContext context) =>
                        context.cmd.DrawRendererList(pass.renderers));
                }

                var blurDesc = graph.GetTextureDesc(source);
                blurDesc.name = "Nilo quarter resolution bloom";
                blurDesc.width = Mathf.Max(1, blurDesc.width / 4);
                blurDesc.height = Mathf.Max(1, blurDesc.height / 4);
                blurDesc.colorFormat = GraphicsFormat.R16G16B16A16_SFloat;
                blurDesc.msaaSamples = MSAASamples.None;
                blurDesc.bindTextureMS = false;
                blurDesc.memoryless = RenderTextureMemoryless.None;
                blurDesc.clearBuffer = false;
                blurDesc.filterMode = FilterMode.Bilinear;
                var extracted = graph.CreateTexture(blurDesc);
                var horizontal = graph.CreateTexture(blurDesc);
                bloom = graph.CreateTexture(blurDesc);
                var extraction = new MaterialPropertyBlock();
                extraction.SetVector(BloomSettings, new Vector4(volume.bloomThreshold.value,
                    volume.characterBloom.value, volume.backgroundBloom.value, 0f));
                AddAuxiliaryBlit(graph, source, mask, extracted, extraction, 0, MaskTexture, "Nilo bloom extraction");
                // shortcut: single-scale glow, use a multiscale bloom pyramid for cinematic wide halos.
                AddBlur(graph, extracted, horizontal, new Vector2(volume.bloomRadius.value / blurDesc.width, 0f));
                AddBlur(graph, horizontal, bloom, new Vector2(0f, volume.bloomRadius.value / blurDesc.height));
            }

            var outputDesc = graph.GetTextureDesc(source);
            outputDesc.name = "Nilo anime color";
            outputDesc.msaaSamples = MSAASamples.None;
            outputDesc.bindTextureMS = false;
            outputDesc.clearBuffer = false;
            var destination = graph.CreateTexture(outputDesc);
            var composite = new MaterialPropertyBlock();
            composite.SetVector(PostSettings, new Vector4(volume.postSaturation.value,
                volume.postContrast.value, volume.colorSteps.value, bloom.IsValid() ? 1f : 0f));
            if (bloom.IsValid())
                AddAuxiliaryBlit(graph, source, bloom, destination, composite, 2, BloomTexture, "Nilo anime composite");
            else
                graph.AddBlitPass(new RenderGraphUtils.BlitMaterialParameters(source, destination, material, 2, composite,
                    RenderGraphUtils.FullScreenGeometryType.ProceduralTriangle),
                    passName: "Nilo anime color");
            resources.cameraColor = destination;
        }

        void AddBlur(RenderGraph graph, TextureHandle source, TextureHandle destination, Vector2 direction)
        {
            var properties = new MaterialPropertyBlock();
            properties.SetVector(BlurDirection, new Vector4(direction.x, direction.y, 0f, 0f));
            graph.AddBlitPass(new RenderGraphUtils.BlitMaterialParameters(source, destination, material, 1, properties,
                RenderGraphUtils.FullScreenGeometryType.ProceduralTriangle),
                passName: "Nilo bloom blur");
        }

        void AddAuxiliaryBlit(RenderGraph graph, TextureHandle source, TextureHandle auxiliary,
            TextureHandle destination, MaterialPropertyBlock properties, int passIndex, int auxiliaryId, string name)
        {
            // Two sampled graph textures need explicit dependency declarations and execution-time bindings.
            using var builder = graph.AddRasterRenderPass<BlitData>(name, out var data);
            data.source = source;
            data.auxiliary = auxiliary;
            data.material = material;
            data.properties = properties;
            data.passIndex = passIndex;
            data.auxiliaryId = auxiliaryId;
            builder.UseTexture(source, AccessFlags.Read);
            builder.UseTexture(auxiliary, AccessFlags.Read);
            builder.SetRenderAttachment(destination, 0, AccessFlags.Write);
            builder.SetRenderFunc(static (BlitData pass, RasterGraphContext context) =>
            {
                pass.properties.SetTexture(BlitTexture, pass.source);
                pass.properties.SetTexture(pass.auxiliaryId, pass.auxiliary);
                pass.properties.SetVector(BlitScaleBias, new Vector4(1f, 1f, 0f, 0f));
                context.cmd.DrawProcedural(Matrix4x4.identity, pass.material, pass.passIndex,
                    MeshTopology.Triangles, 3, 1, pass.properties);
            });
        }
    }
}
