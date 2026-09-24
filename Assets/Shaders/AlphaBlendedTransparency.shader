Shader "Basics/AlphaBlendedTransparency"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        
        // 【关键】使用 [Enum] 特性将整数属性映射为 BlendMode 下拉菜单
        // 值 5 = SrcAlpha，即源颜色乘以自身 Alpha 作为混合权重
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Source Blend Mode", Integer) = 5
        
        // 值 10 = OneMinusSrcAlpha，即目标颜色乘以 (1 - 源Alpha) 作为混合权重
        // 默认组合 (5, 10) 构成标准 Alpha Blending：out = src * srcA + dst * (1 - srcA)
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Destination Blend Mode", Integer) = 10
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            
            // 【关键】RenderType 标记为 Transparent
            // URP 根据此标签将物体归入透明渲染通道，与不透明物体分离处理
            "RenderType" = "Transparent"
            
            // 【关键】Queue 设为 Transparent（3000）
            // 确保在所有 Geometry(2000) 不透明物体绘制完成后才渲染
            // 避免透明物体被错误地写入深度缓冲导致后方物体被剔除
            "Queue" = "Transparent"
        }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }

            // 【核心】动态混合模式指令
            // 方括号语法允许从材质属性实时读取混合因子
            // 无需编写多个 Shader 变体即可支持 Additive、Multiply、Premultiplied 等多种混合
            Blend [_SrcBlend] [_DstBlend]
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST;
            CBUFFER_END

            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture);

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert(appdata v)
            {
                v2f o = (v2f)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);

                return o;
            }

            float4 frag(v2f i) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(i);
                
                // 纹理采样后直接乘以基色
                // Alpha 通道保留原始乘积结果，由硬件 Blend 单元在光栅化阶段执行混合
                // 片元着色器输出的是“源颜色”，而非最终帧缓冲颜色
                float4 textureColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv);
                return textureColor * _BaseColor;
            }

            ENDHLSL
        }
    }
}