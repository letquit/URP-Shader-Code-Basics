Shader "Basics/PostProcess/Silhouette"
{
    SubShader
    {
        Tags
        {
            // 声明专用于 URP，确保正确的编译路径和关键字变体生成
            "RenderPipeline" = "UniversalPipeline"
        }
        
        Pass
        {
            // 后处理标准渲染状态三件套
            ZTest Always  // 无视深度测试，全屏绘制
            Cull Off      // 关闭背面剔除
            ZWrite Off    // 不写入深度，避免污染后续 Pass
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            // URP 核心库：提供 Varyings、_ZBufferParams 等基础定义
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // Blit 工具库：提供内置 Vert() 顶点着色器、_BlitTexture 和 sampler
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            // 【核心】深度纹理声明头文件
            // 提供 SampleSceneDepth() 函数和 _CameraDepthTexture 的自动绑定
            // 此头文件与 ConfigureInput(ScriptableRenderPassInput.Depth) 配对使用
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // 由 SilhouetteFeature.RecordRenderGraph 通过 material.SetColor/SetFloat 传入
            float4 _NearColor;   // 近处颜色（depth ≈ 0）
            float4 _FarColor;    // 远处颜色（depth ≈ 1）
            float _DepthPower;   // 深度映射曲线的幂次控制

            float4 frag(Varyings i) : SV_Target
            {
                // 【步骤1】采样原始非线性深度
                // SampleSceneDepth 内部处理了平台差异：
                //   - Metal/Vulkan: 直接采样硬件深度缓冲
                //   - OpenGL ES: 采样 URP 自动生成的 _CameraDepthTexture 拷贝
                // 返回值范围 [0, 1]，但分布是非线性的（近处精度高、远处精度低）
                float rawDepth = SampleSceneDepth(i.texcoord);
                
                // 【步骤2】转换为线性 [0, 1] 深度
                // Linear01Depth 使用 _ZBufferParams 还原真实世界距离比例
                // _ZBufferParams 由 URP 自动设置，包含近远裁剪面和投影矩阵信息
                // ⚠️ 不做此转换直接用 rawDepth 做 lerp 会导致渐变集中在近处
                float linearDepth = Linear01Depth(rawDepth, _ZBufferParams);

                // 【步骤3】应用艺术化幂次曲线
                // pow(linearDepth, power) 重塑深度到颜色的映射关系：
                //   power = 1.0 → 线性过渡（物理准确）
                //   power < 1.0 → 近处过渡更缓，强调前景轮廓
                //   power > 1.0 → 远处过渡更缓，适合雾效/大气透视
                float depth = pow(linearDepth, _DepthPower);

                // 【步骤4】在近色和远色之间插值
                // depth=0 (近裁面) → _NearColor
                // depth=1 (远裁面) → _FarColor
                // Alpha 通道也参与插值，支持透明轮廓/雾效混合
                return lerp(_NearColor, _FarColor, depth);
            }
            
            ENDHLSL
        }
    }
}