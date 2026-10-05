using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

/// <summary>
/// 边缘检测/描边后处理 RendererFeature
/// </summary>
public class OutlineFeature : ScriptableRendererFeature
{
    private OutlineRenderPass pass = new();

    public override void Create()
    {
        name = "Outline";
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var settings = VolumeManager.instance.stack.GetComponent<OutlineSettings>();

        // 仅当 Volume 存在且激活时入队 Pass
        // IsActive() 内部检查 strength > 0，避免无效 GPU 开销
        if (settings != null && settings.IsActive())
        {
            renderer.EnqueuePass(pass);
        }
    }

    class OutlineRenderPass : ScriptableRenderPass
    {
        private Material material;

        public OutlineRenderPass()
        {
            profilingSampler = new ProfilingSampler("Outline Post Process");
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            
            // 【关键】标记需要中间纹理
            // 虽然本实现手动管理拷贝以获得更精细控制，
            // 但此标志告知 URP 框架该 Pass 存在读写竞争
            requiresIntermediateTexture = true;
        }
        
        private void FindMaterial()
        {
            if (material != null) return;
            var shader = Shader.Find("Basics/PostProcess/Outline");
            material = new Material(shader);
            // ⚠️ 生产环境应改用序列化引用或 Resources.Load
        }

        /// <summary>
        /// 构建颜色拷贝纹理的描述符
        /// </summary>
        /// <remarks>
        /// MSAA 设为 1：拷贝后的纹理仅用于全屏 Blit 采样，无需多重采样
        /// DepthBits.None：纯颜色拷贝不需要深度缓冲，节省显存
        /// </remarks>
        private static RenderTextureDescriptor GetCopyPassDescriptor(RenderTextureDescriptor descriptor)
        {
            descriptor.msaaSamples = 1;
            descriptor.depthBufferBits = (int)DepthBits.None;
            return descriptor;
        }

        // ===== Pass Data 定义 =====
        
        private class CopyPassData
        {
            public TextureHandle inputTexture;
        }

        private class MainPassData
        {
            public Material material;
            public TextureHandle inputTexture;
        }
        
        // ===== 静态执行函数（避免闭包分配）=====
        
        /// <summary>
        /// 颜色拷贝 Pass：将 activeColorTexture 复制到临时 RT
        /// 使用无材质 Blit（passIndex=0, false），纯硬件拷贝零 Shader 开销
        /// </summary>
        private static void ExecuteCopyPass(RasterCommandBuffer cmd, CopyPassData data)
        {
            Blitter.BlitTexture(cmd, data.inputTexture, new Vector4(1, 1, 0, 0), 0.0f, false);
        }

        /// <summary>
        /// 主 Pass：从拷贝纹理读取 → 边缘检测 → 写入 activeColorTexture
        /// </summary>
        private static void ExecuteMainPass(RasterCommandBuffer cmd, MainPassData data)
        {
            Blitter.BlitTexture(cmd, data.inputTexture, new Vector4(1, 1, 0, 0), data.material, 0);
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            FindMaterial();

            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            // 【核心】创建颜色缓冲副本
            // 解决 Read-Write Hazard：MainPass 需同时读取原图和写入原图
            // 通过拷贝将"读源"和"写目标"分离为两张不同纹理
            var colorCopyDescriptor = GetCopyPassDescriptor(cameraData.cameraTargetDescriptor);
            var colorCopy = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph, colorCopyDescriptor, "_OutlineColorCopy", false);

            // 设置材质参数（CPU 端录制阶段）
            var settings = VolumeManager.instance.stack.GetComponent<OutlineSettings>();
            material.SetFloat("_Strength", settings.strength.value);
            material.SetColor("_OutlineColor", settings.outlineColor.value);
            material.SetFloat("_ColorThreshold", settings.colorThreshold.value);

            // ===== Pass 1: 颜色拷贝 =====
            using (var builder = renderGraph.AddRasterRenderPass<CopyPassData>(
                "Outline_CopyColor", out var passData, profilingSampler))
            {
                passData.inputTexture = resourceData.activeColorTexture;
                
                // 读取原始颜色缓冲
                builder.UseTexture(resourceData.activeColorTexture, AccessFlags.Read);
                // 写入临时拷贝纹理
                builder.SetRenderAttachment(colorCopy, 0, AccessFlags.Write);
                
                builder.SetRenderFunc(static (CopyPassData data, RasterGraphContext context) 
                    => ExecuteCopyPass(context.cmd, data));
            }

            // ===== Pass 2: 边缘检测 + 合成 =====
            using (var builder = renderGraph.AddRasterRenderPass<MainPassData>(
                "Outline_MainPass", out var passData, profilingSampler))
            {
                passData.material = material;
                passData.inputTexture = colorCopy; // 从拷贝纹理读取，非原始缓冲
                
                // 读取拷贝纹理作为边缘检测输入
                builder.UseTexture(colorCopy, AccessFlags.Read);
                // 写回原始颜色缓冲（此时无读写冲突）
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0, AccessFlags.Write);
                
                builder.SetRenderFunc(static (MainPassData data, RasterGraphContext context) 
                    => ExecuteMainPass(context.cmd, data));
            }
        }
    } 
}