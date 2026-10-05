Shader "Basics/PostProcess/Greyscale"
{
    SubShader
    {
        Tags
        {
            // 【关键】声明此 Shader 专用于 URP
            // 缺少此 Tag 时，URP 可能在某些渲染路径中跳过或错误编译此 Shader
            "RenderPipeline" = "UniversalPipeline"
        }
        
        Pass
        {
            // ===== 后处理专用渲染状态 =====
            // ZTest Always: 无视深度缓冲，确保全屏绘制不被任何物体遮挡
            // Cull Off:     关闭背面剔除（Blit 绘制的三角形朝向可能翻转）
            // ZWrite Off:   不写入深度，避免污染后续 Pass 的深度测试
            ZTest Always
            Cull Off
            ZWrite Off
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            // URP Core：提供 Varyings 结构体定义等基础类型
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // 【核心】Blit 工具库
            // 提供内置的 Vert() 顶点着色器和 _BlitTexture / sampler_PointClamp
            // 使 Shader 无需自定义顶点输入/输出结构体和纹理声明
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            // 颜色工具库：提供 Luminance() 等标准色彩空间转换函数
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            // 由 GreyscaleFeature.RecordRenderGraph 通过 material.SetFloat 传入
            float _Strength;

            // 【注意】顶点着色器直接使用 Blit.hlsl 内置的 Vert()
            // 它自动生成覆盖全屏的三角形并计算正确的 UV
            // 无需手写 appdata / v2f 结构和 TransformObjectToHClip 等调用

            float4 frag(Varyings i) : SV_Target
            {
                // 采样输入纹理（由 Render Graph 自动绑定到 _BlitTexture）
                // sampler_PointClamp: 点采样+钳制，后处理通常不需要双线性过滤
                float4 originalColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, i.texcoord);
                
                // 【核心】ITU-R BT.709 标准亮度公式
                // Luminance(rgb) = dot(rgb, float3(0.2126, 0.7152, 0.0722))
                // 返回 float3 灰度值（RGB 三通道相同），保留感知亮度一致性
                float3 newColor = Luminance(originalColor.rgb);

                // 根据 _Strength 在原始颜色和灰度之间线性插值
                // _Strength=0 → 完全原始颜色；_Strength=1 → 完全灰度
                // Alpha 通道始终保持不变，避免影响透明合成
                return float4(lerp(originalColor.rgb, newColor, _Strength), originalColor.a);
            }
            
            ENDHLSL
        }
    }
}