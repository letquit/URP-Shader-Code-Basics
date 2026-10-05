using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

/// <summary>
/// 灰度后处理 RendererFeature
/// 作为渲染管线的扩展点，负责创建和条件性注入渲染 Pass
/// </summary>
public class GreyscaleFeature : ScriptableRendererFeature
{
    // Pass 实例在 Feature 生命周期内复用，避免每帧 GC
    private GreyscaleRenderPass pass = new();

    public override void Create()
    {
        name = "Greyscale";
        // 可在此处初始化 Pass 的固定配置（如 Shader 查找）
    }

    /// <summary>
    /// 每帧由 URP 调用，决定是否将 Pass 加入渲染队列
    /// </summary>
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // 【关键】从 Volume Stack 获取当前生效的设置
        // VolumeManager 自动处理全局/局部 Volume 的混合与优先级
        var settings = VolumeManager.instance.stack.GetComponent<GreyscaleSettings>();

        // 仅在效果激活时入队，避免无效 Pass 消耗 GPU 资源
        if (settings != null && settings.IsActive())
        {
            renderer.EnqueuePass(pass);
        }
    }

    /// <summary>
    /// 灰度后处理渲染 Pass（Render Graph 版本）
    /// </summary>
    class GreyscaleRenderPass : ScriptableRenderPass
    {
        private Material material;

        public GreyscaleRenderPass()
        {
            profilingSampler = new ProfilingSampler("Greyscale Post Process");
            
            // 【关键】AfterRenderingPostProcessing 确保在 URP 内置后处理之后执行
            // 若设为 BeforeRenderingPostProcessing，则灰度会被 Bloom/Tonemap 覆盖
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            
            // 声明需要中间纹理拷贝（非原位操作）
            requiresIntermediateTexture = true;
        }
        
        /// <summary>
        /// 延迟查找 Shader 并缓存 Material
        /// 避免在构造函数中查找（此时 Shader 可能未加载）
        /// </summary>
        private void FindMaterial()
        {
            if (material != null) return;

            var shader = Shader.Find("Basics/PostProcess/Greyscale");
            material = new Material(shader);
            // ⚠️ 生产环境建议改用 Resources.Load 或 AssetReference
            // Shader.Find 在构建后可能因 Strip 而返回 null
        }

        /// <summary>
        /// 生成拷贝用 RT 描述符：去除 MSAA 和深度缓冲
        /// 后处理只需单采样颜色缓冲，节省显存带宽
        /// </summary>
        private static RenderTextureDescriptor GetCopyPassDescriptor(RenderTextureDescriptor descriptor)
        {
            descriptor.msaaSamples = 1;
            descriptor.depthBufferBits = (int)DepthBits.None;
            return descriptor;
        }

        // ===== Render Graph Pass Data =====
        // RG 要求将所有执行数据封装为 class，通过 builder 传递
        // 禁止在 Execute 函数中捕获外部变量（闭包会导致 RG 编译失败）

        private class CopyPassData
        {
            public TextureHandle inputTexture;
        }

        private class MainPassData
        {
            public Material material;
            public TextureHandle inputTexture;
        }
        
        /// <summary>
        /// 拷贝 Pass 执行函数：将当前活跃颜色缓冲复制到中间纹理
        /// static + RasterCommandBuffer 是 RG 的强制签名要求
        /// </summary>
        private static void ExecuteCopyPass(RasterCommandBuffer cmd, CopyPassData data)
        {
            // Blitter.BlitTexture 是 RG 兼容的全屏拷贝 API
            // Vector4(1,1,0,0) = UV 缩放偏移，0.0f = mip level，false = 不双线性过滤
            Blitter.BlitTexture(cmd, data.inputTexture, new Vector4(1, 1, 0, 0), 0.0f, false);
        }

        /// <summary>
        /// 主 Pass 执行函数：应用灰度材质到中间纹理，输出回活跃颜色缓冲
        /// </summary>
        private static void ExecuteMainPass(RasterCommandBuffer cmd, MainPassData data)
        {
            // 带 Material 参数的 Blit 会绑定材质并绘制全屏三角形
            // 材质的 _Strength 等参数需在 RecordRenderGraph 中提前设置
            Blitter.BlitTexture(cmd, data.inputTexture, new Vector4(1, 1, 0, 0), data.material, 0);
        }

        /// <summary>
        /// 【核心】Render Graph 录制入口（替代旧版 Execute）
        /// 仅声明资源和依赖，不执行任何 GPU 命令
        /// </summary>
        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            FindMaterial();

            // 从帧数据容器获取 URP 资源和相机信息
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            // 创建中间拷贝纹理（RG 自动管理分配/释放/别名）
            var colorCopyDescriptor = GetCopyPassDescriptor(cameraData.cameraTargetDescriptor);
            var colorCopy = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph, colorCopyDescriptor, "_GreyscaleColorCopy", false);

            // 【关键】在录制阶段设置材质参数（非执行阶段）
            // RG 保证参数在实际绘制前生效
            var settings = VolumeManager.instance.stack.GetComponent<GreyscaleSettings>();
            material.SetFloat("_Strength", settings.strength.value);

            // ===== Pass 1: 拷贝当前帧颜色到中间纹理 =====
            using (var builder = renderGraph.AddRasterRenderPass<CopyPassData>(
                "Greyscale_CopyColor", out var passData, profilingSampler))
            {
                passData.inputTexture = resourceData.activeColorTexture;
                
                // 显式声明资源访问权限（RG 据此做屏障插入和 Pass 重排）
                builder.UseTexture(resourceData.activeColorTexture, AccessFlags.Read);
                builder.SetRenderAttachment(colorCopy, 0, AccessFlags.Write);
                
                // 绑定静态执行函数（不允许 lambda 捕获）
                builder.SetRenderFunc(static (CopyPassData data, RasterGraphContext context) 
                    => ExecuteCopyPass(context.cmd, data));
            }

            // ===== Pass 2: 灰度处理并写回颜色缓冲 =====
            using (var builder = renderGraph.AddRasterRenderPass<MainPassData>(
                "Greyscale_MainPass", out var passData, profilingSampler))
            {
                passData.material = material;
                passData.inputTexture = colorCopy;
                
                builder.UseTexture(colorCopy, AccessFlags.Read);
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0, AccessFlags.Write);
                
                builder.SetRenderFunc(static (MainPassData data, RasterGraphContext context) 
                    => ExecuteMainPass(context.cmd, data));
            }
        }
    } 
}