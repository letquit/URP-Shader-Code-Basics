Shader "Basics/ScrollingTextures"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        // 滚动速度向量：X 控制水平流速，Y 控制垂直流速
        // Vector 类型在 Inspector 中显示为四分量，但实际仅使用 xy 分量
        _ScrollSpeed("Scroll Speed", Vector) = (0, 0, 0, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // 【关键】引入全局采样器库，提供预定义的采样器状态（如 sampler_LinearRepeat）
            // 避免为每个纹理单独声明采样器，减少 GPU 状态切换开销
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                // 滚动速度作为逐材质属性纳入 SRP Batcher 常量缓冲
                // 修改速度时仅更新该缓冲区指针，不触发 Shader 重绑定
                float2 _ScrollSpeed;
            CBUFFER_END

            TEXTURE2D(_BaseTexture);
            // 【注意】此处未声明 SAMPLER(sampler_BaseTexture)
            // 改用 GlobalSamplers.hlsl 中的全局采样器 sampler_LinearRepeat
            // 多个滚动纹理可共享同一采样器状态，提升合批效率

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
                // UV 变换仅应用 Tiling/Offset，不包含时间偏移
                // 将时间相关计算推迟到片元阶段，避免顶点动画导致的缓存失效
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);

                return o;
            }

            float4 frag(v2f i) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(i);

                // 【核心动画】UV + 速度 × 时间
                // _Time.y 为自场景启动以来的秒数（float），由引擎每帧自动上传
                // 结果超出 [0,1] 范围时由采样器的 Repeat 模式自动取模，实现无缝循环
                float2 uv = i.uv + _ScrollSpeed * _Time.y;

                // 使用全局线性重复采样器进行纹理采样
                // sampler_LinearRepeat = 双线性过滤 + UV 循环包裹，适合连续滚动效果
                float4 textureColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_LinearRepeat, uv);

                return textureColor * _BaseColor;
            }

            ENDHLSL
        }

        Pass
        {
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex depthOnlyVert
            #pragma fragment depthOnlyFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 positionOS : POSITION;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
            };

            v2f depthOnlyVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                return o;
            }

            float depthOnlyFrag(v2f i) : SV_TARGET
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }

        Pass
        {
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On

            HLSLPROGRAM
            #pragma vertex depthNormalsVert
            #pragma fragment depthNormalsFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
            };

            v2f depthNormalsVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.normalWS = NormalizeNormalPerVertex(normalWS);
                return o;
            }

            float4 depthNormalsFrag(v2f i) : SV_TARGET
            {
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                return float4(normalWS, 0.0f);
            }
            ENDHLSL
        }
    }
}