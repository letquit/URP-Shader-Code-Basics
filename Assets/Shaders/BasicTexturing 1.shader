Shader "Basics/BasicTexturing 1"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _BaseTexture("Base Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        // ==================== Pass 0: 主颜色输出 ====================
        Pass
        {            
            Tags { "LightMode" = "SRPDefaultUnlit" }
            
            // 【显式声明】虽然 Opaque 队列默认开启这些状态，
            // 但显式写出可避免后续修改 Queue 时遗漏导致渲染错误
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // SRP Batcher 兼容：所有材质属性必须在此缓冲区内连续声明
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST; // Tiling & Offset，TRANSFORM_TEX 宏依赖此变量
            CBUFFER_END

            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture);

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f vert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                // 应用材质面板中的 Tiling/Offset 变换
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                return o;
            }

            float4 frag(v2f i) : SV_TARGET
            {
                float4 textureColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv);
                return textureColor * _BaseColor;
            }
            ENDHLSL
        }

        // ==================== Pass 1: 纯深度写入 ====================
        Pass
        {
            // 【关键】URP 在以下场景自动调度此 Pass：
            // 1. 阴影贴图生成（当 ShadowCaster 缺失时的回退）
            // 2. 深度预填充（Depth Prepass）
            // 3. 屏幕空间特效的深度采样源
            Tags { "LightMode" = "DepthOnly" }
            
            ZWrite On
            // 【优化】ColorMask R 仅写入红色通道
            // 深度信息实际由 ZWrite 写入深度缓冲，颜色缓冲写入被最小化
            // 相比 ColorMask 0（完全禁止），R 通道保留可避免某些 GPU 驱动的空片元优化问题
            ColorMask R
            
            HLSLPROGRAM
            #pragma vertex depthOnlyVert
            #pragma fragment depthOnlyFrag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct appdata { float4 positionOS : POSITION; };
            struct v2f { float4 positionCS : SV_POSITION; };

            v2f depthOnlyVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                return o;
            }

            // 返回裁剪空间 Z 值，GPU 硬件自动将其转换为非线性深度写入深度缓冲
            float depthOnlyFrag(v2f i) : SV_TARGET
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }

        // ==================== Pass 2: 深度+法线编码 ====================
        Pass
        {
            // 【关键】URP 的后处理效果（SSAO、SSR、Outline）依赖此 Pass
            // 将世界空间法线编码到 RGBA 输出，同时写入深度缓冲
            Tags { "LightMode" = "DepthNormals" }
            
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex depthNormalsVert
            #pragma fragment depthNormalsFrag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct appdata
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL; // 需要法线输入，与 DepthOnly Pass 不同
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0; // 传递世界空间法线到片元阶段
            };

            v2f depthNormalsVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                
                // 模型空间法线 → 世界空间法线
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                // 顶点级归一化：减少片元插值后的长度偏差
                o.normalWS = NormalizeNormalPerVertex(normalWS);
                return o;
            }

            float4 depthNormalsFrag(v2f i) : SV_TARGET
            {
                // 片元级重新归一化：消除顶点插值导致的法线非单位长度问题
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);

                // 将 [-1,1] 法线映射到 [0,1] 颜色空间存储
                // URP 后处理解码时使用相同逆运算还原法线方向
                return float4(normalWS, 0.0f);
            }
            ENDHLSL
        }
    }
}