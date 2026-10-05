Shader "Basics/PostProcess/Outline"
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
            ZWrite Off    // 不写入深度缓冲
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            // URP 核心库：提供 Varyings、采样宏等基础定义
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // Blit 工具库：提供内置 Vert() 顶点着色器、_BlitTexture 及其采样器
            // ⚠️ _BlitTexture 由 OutlineFeature.CopyPass 填充的颜色拷贝纹理
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            // 由 OutlineFeature.RecordRenderGraph 通过 material.SetFloat/SetColor 传入
            float _Strength;       // 描边混合强度 [0, 1]
            float3 _OutlineColor;  // 描边颜色（RGB，无 Alpha）
            float _ColorThreshold; // 边缘判定阈值 [0, 1]

            float4 frag(Varyings i) : SV_Target
            {
                // 【步骤1】采样原始像素颜色（Point 采样，精确还原单像素值）
                // 用于最终与原图的 lerp 混合，保留原始细节
                float4 originalColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, i.texcoord);

                // 【步骤2】构建 Roberts Cross 算子的四个采样点
                // _BlitTexture_TexelSize.xy = (1/width, 1/height)，即一个纹素的 UV 尺寸
                // Roberts Cross 使用对角线方向的 2×2 邻域差分：
                //   col0(BL) ←→ col1(TR) 构成左上-右下对角线梯度
                //   col2(BR) ←→ col3(TL) 构成右上-左下对角线梯度
                float2 blUV = i.texcoord + float2(0.0f, 0.0f);                           // Bottom-Left
                float2 trUV = i.texcoord + float2(_BlitTexture_TexelSize.x, _BlitTexture_TexelSize.y); // Top-Right
                float2 brUV = i.texcoord + float2(_BlitTexture_TexelSize.x, 0.0f);       // Bottom-Right
                float2 tlUV = i.texcoord + float2(0.0f, _BlitTexture_TexelSize.y);       // Top-Left

                // 【步骤3】Linear 采样四个邻域颜色
                // 使用 LinearClamp 而非 PointClamp：在纹素边界处自动双线性插值
                // 使梯度计算更平滑，减少锯齿状伪边缘
                float3 col0 = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, blUV).rgb;
                float3 col1 = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, trUV).rgb;
                float3 col2 = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, brUV).rgb;
                float3 col3 = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, tlUV).rgb;

                // 【步骤4】计算两个对角线方向的 RGB 梯度向量
                float3 grad0 = col1 - col0;  // 左上→右下方向的颜色变化率
                float3 grad1 = col3 - col2;  // 右上→左下方向的颜色变化率

                // 【步骤5】合并梯度幅值作为边缘强度
                // sqrt(|grad0|² + |grad1|²) 等价于 Roberts Cross 的梯度模长
                // dot(grad, grad) 比 length(grad) 更高效（避免多余 sqrt）
                float edge = sqrt(dot(grad0, grad0) + dot(grad1, grad1));
                
                // 【步骤6】阈值硬切割 + 强度调制
                // 超过阈值 → 标记为边缘，乘以 _Strength 控制混合程度
                // 未超阈值 → 非边缘区域，edge=0，lerp 结果完全等于原图
                // ⚠️ 此处为硬阈值（step），若需柔和过渡可改用 smoothstep
                edge = edge > _ColorThreshold ? _Strength : 0.0f;

                // 【步骤7】在原图和描边颜色之间按边缘强度插值
                // edge=0 → 输出 originalColor（非边缘区域保持原样）
                // edge=_Strength → 向 _OutlineColor 偏移（边缘区域着色）
                // Alpha 始终保留原图值，描边不影响透明度
                return float4(lerp(originalColor.rgb, _OutlineColor, edge), originalColor.a);
            }
            
            ENDHLSL
        }
    }
}