using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

/// <summary>
/// 轮廓/深度渐变后处理 RendererFeature
/// </summary>
public class SilhouetteFeature : ScriptableRendererFeature
{
    private SilhouetteRenderPass pass = new();

    public override void Create()
    {
        name = "Silhouette";
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var settings = VolumeManager.instance.stack.GetComponent<SilhouetteSettings>();

        if (settings != null && settings.IsActive())
        {
            renderer.EnqueuePass(pass);
        }
    }

    class SilhouetteRenderPass : ScriptableRenderPass
    {
        private Material material;

        public SilhouetteRenderPass()
        {
            profilingSampler = new ProfilingSampler("Silhouette Post Process");
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            
            // 【关键区别】不需要中间纹理拷贝
            // 此 Pass 读取深度 + 读取颜色 → 写入颜色，无 Read-Write Hazard
            // 设为 false 可节省一次全屏 Blit 和一张临时 RT 的显存开销
            requiresIntermediateTexture = false;
        }
        
        private void FindMaterial()
        {
            if (material != null) return;
            var shader = Shader.Find("Basics/PostProcess/Silhouette");
            material = new Material(shader);
            // ⚠️ 生产环境应改用序列化引用或 Resources.Load
        }

        private class MainPassData
        {
            public Material material;
            public TextureHandle inputTexture;
        }

        private static void ExecuteMainPass(RasterCommandBuffer cmd, MainPassData data)
        {
            // 单步 Blit：读取 inputTexture + 深度纹理 → 应用材质 → 写回
            // 深度纹理由 ConfigureInput 自动绑定，无需显式传入 PassData
            Blitter.BlitTexture(cmd, data.inputTexture, new Vector4(1, 1, 0, 0), data.material, 0);
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            FindMaterial();
            
            // 【核心】声明深度纹理输入依赖
            // 告知 RG 此 Pass 需要读取深度缓冲，RG 据此：
            //   1. 确保深度纹理在此 Pass 之前已完成写入
            //   2. 插入必要的资源屏障（Barrier）
            //   3. 在不支持原生深度采样的平台上自动创建深度拷贝
            ConfigureInput(ScriptableRenderPassInput.Depth);

            var resourceData = frameData.Get<UniversalResourceData>();

            // 批量设置材质参数（录制阶段执行，非 GPU 命令）
            var settings = VolumeManager.instance.stack.GetComponent<SilhouetteSettings>();
            material.SetColor("_NearColor", settings.nearColor.value);
            material.SetColor("_FarColor", settings.farColor.value);
            material.SetFloat("_DepthPower", settings.depthPower.value);

            using (var builder = renderGraph.AddRasterRenderPass<MainPassData>(
                "Silhouette_MainPass", out var passData, profilingSampler))
            {
                passData.material = material;
                passData.inputTexture = resourceData.activeColorTexture;
                
                // 显式声明深度纹理只读访问
                // 与 ConfigureInput 配合使用：ConfigureInput 声明逻辑依赖，
                // UseTexture 声明物理资源访问权限
                builder.UseTexture(resourceData.activeDepthTexture, AccessFlags.Read);
                
                // 颜色缓冲作为渲染目标写入
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0, AccessFlags.Write);
                
                builder.SetRenderFunc(static (MainPassData data, RasterGraphContext context) 
                    => ExecuteMainPass(context.cmd, data));
            }
        }
    } 
}