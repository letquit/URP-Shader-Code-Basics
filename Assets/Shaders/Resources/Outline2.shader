Shader "Basics/PostProcess/Outline2"
{
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
        }
        
        Pass
        {
            ZTest Always
            Cull Off
            ZWrite Off
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            float _Strength;
            float3 _OutlineColor;
            float _ColorThreshold;
            float _DepthThreshold;
            float _NormalThreshold;

            float4 frag(Varyings i) : SV_Target
            {
                float4 originalColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, i.texcoord);

                // Roberts Cross 四个对角采样点
                float2 blUV = i.texcoord + float2(0.0f, 0.0f);
                float2 trUV = i.texcoord + float2(_BlitTexture_TexelSize.x, _BlitTexture_TexelSize.y);
                float2 brUV = i.texcoord + float2(_BlitTexture_TexelSize.x, 0.0f);
                float2 tlUV = i.texcoord + float2(0.0f, _BlitTexture_TexelSize.y);

                // 颜色边缘
                float3 col0 = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, blUV).rgb;
                float3 col1 = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, trUV).rgb;
                float3 col2 = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, brUV).rgb;
                float3 col3 = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, tlUV).rgb;

                float3 colorGrad0 = col1 - col0;
                float3 colorGrad1 = col3 - col2;
                float colorEdge = sqrt(dot(colorGrad0, colorGrad0) + dot(colorGrad1, colorGrad1));
                colorEdge = colorEdge > _ColorThreshold ? _Strength : 0.0f;

                // 深度边缘（线性 01 深度，避免非线性 Z 把近处梯度挤扁）
                float depth0 = Linear01Depth(SampleSceneDepth(blUV), _ZBufferParams);
                float depth1 = Linear01Depth(SampleSceneDepth(trUV), _ZBufferParams);
                float depth2 = Linear01Depth(SampleSceneDepth(brUV), _ZBufferParams);
                float depth3 = Linear01Depth(SampleSceneDepth(tlUV), _ZBufferParams);

                float depthGrad0 = depth1 - depth0;
                float depthGrad1 = depth3 - depth2;
                float depthEdge = sqrt(depthGrad0 * depthGrad0 + depthGrad1 * depthGrad1);
                depthEdge = depthEdge > _DepthThreshold ? _Strength : 0.0f;

                // 法线边缘
                float3 normal0 = SampleSceneNormals(blUV);
                float3 normal1 = SampleSceneNormals(trUV);
                float3 normal2 = SampleSceneNormals(brUV);
                float3 normal3 = SampleSceneNormals(tlUV);

                float3 normGrad0 = normal1 - normal0;
                float3 normGrad1 = normal3 - normal2;
                float normalEdge = sqrt(dot(normGrad0, normGrad0) + dot(normGrad1, normGrad1));
                normalEdge = normalEdge > _NormalThreshold ? _Strength : 0.0f;

                float edge = max(max(colorEdge, depthEdge), normalEdge);
                return float4(lerp(originalColor.rgb, _OutlineColor, edge), originalColor.a);
            }
            ENDHLSL
        }
    }
}
