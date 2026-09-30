Shader "Basics/BasicLighting"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        _NormalTexture("Normal Texture", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0.0, 2.0)) = 1.0
        // 注意：此属性在 CBUFFER 中声明为 float3，但 Properties 定义为 Color
        // Unity 会自动截取 RGB 分量，但建议统一类型避免混淆
        _AmbientLighting("Ambient Lighting", Color) = (0.2, 0.2, 0.2, 1)
        // 光泽度以 2^n 指数形式影响高光范围，值越大高光越锐利
        _Glossiness("Glossiness", Float) = 1
        _FresnelPower("Fresnel Power", Range(1.0, 20.0)) = 4.0
        _FresnelStrength("Fresnel Strength", Range(0.0, 1.0)) = 0.15
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        // ==================== Pass 0: 主光照计算 ====================
        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // 【关键】阴影变体编译
            // 根据 URP Asset 设置自动生成对应的阴影采样代码路径
            // 缺少这些指令会导致物体无法接收任何阴影
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // 【关键】引入 URP 光照库
            // 提供 GetMainLight(), SampleSH(), TransformWorldToShadowCoord() 等核心 API
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float _NormalStrength;
                float3 _AmbientLighting; // 仅使用 RGB，Alpha 被丢弃
                float _Glossiness;
                float _FresnelPower;
                float _FresnelStrength;
            CBUFFER_END

            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture);
            TEXTURE2D(_NormalTexture);
            SAMPLER(sampler_NormalTexture);

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT; // 切线空间基向量构建必需
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2; // 世界空间位置用于阴影坐标计算
                float3 viewWS : TEXCOORD3; // 视线方向用于高光与菲涅尔
                float4 tangentWS : TEXCOORD4; // xyz=切线方向, w=手性符号
            };

            v2f vert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.viewWS = GetWorldSpaceViewDir(o.positionWS);
                // w 分量存储切线手性（+1 或 -1），用于修正副法线方向
                o.tangentWS = float4(TransformObjectToWorldDir(v.tangentOS.xyz), v.tangentOS.w);
                return o;
            }

            float4 frag(v2f i) : SV_TARGET
            {
                // 片元级法线归一化，消除顶点插值导致的长度偏差
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                float3 viewWS = normalize(i.viewWS);

                // 【核心】获取主光源信息（含阴影衰减）
                // shadowCoord 由 TransformWorldToShadowCoord 从世界坐标生成
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                // 合并距离衰减与阴影衰减到光照颜色中
                float3 mainLightColor = mainLight.distanceAttenuation
                    * mainLight.shadowAttenuation
                    * mainLight.color;

                // 球谐环境光：基于法线方向的三阶 SH9 近似
                // 比固定 _AmbientLighting 更真实，能响应天空盒颜色变化
                float3 ambientLighting = SampleSH(normalWS);

                // ===== 法线贴图解码与 TBN 矩阵重建 =====
                // UnpackNormalScale 将 [0,1] 纹理值还原为 [-1,1] 切线空间法线
                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalTexture, sampler_NormalTexture, i.uv),
                    _NormalStrength
                );

                // 【关键】副法线 = cross(N, T) * 手性符号 * 变换缩放校正
                // unity_WorldTransformParams.w 补偿非均匀缩放对叉积长度的影响
                float3 binormalWS = cross(normalWS, i.tangentWS.xyz)
                    * i.tangentWS.w
                    * unity_WorldTransformParams.w;

                // TBN 矩阵变换：切线空间法线 → 世界空间法线
                normalWS = normalize(
                    normalTS.x * i.tangentWS.xyz +
                    normalTS.y * binormalWS +
                    normalTS.z * normalWS
                );

                // ===== Lambert 漫反射 =====
                float3 diffuseLighting = saturate(dot(normalWS, mainLight.direction)) * mainLightColor;

                // ===== Blinn-Phong 镜面反射 =====
                // 注意：此处使用的是经典 Phong reflect 而非 Blinn 半角向量
                // pow(2^n, glossiness) 将线性滑块映射为指数级高光锐度
                float3 reflectedVector = reflect(-mainLight.direction, normalWS);
                float3 specularLighting = pow(
                    saturate(dot(reflectedVector, viewWS)),
                    pow(2.0f, _Glossiness)
                ) * mainLightColor;

                // ===== Schlick 菲涅尔边缘光 =====
                // 视角与法线夹角越大，反射越强；_FresnelPower 控制过渡曲线陡度
                float3 fresnelLighting = pow(
                    1.0f - saturate(dot(normalWS, viewWS)),
                    _FresnelPower
                ) * _FresnelStrength;

                // ===== 最终合成 =====
                // 漫反射与环境光乘以 albedo（能量守恒），高光与菲涅尔直接叠加
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv) * _BaseColor;
                float3 finalColor = (ambientLighting + diffuseLighting) * baseColor.rgb
                    + specularLighting
                    + fresnelLighting;

                return float4(finalColor, baseColor.a);
            }
            ENDHLSL
        }

        // ==================== Pass 1: 阴影投射 ====================
        Pass
        {
            Tags
            {
                "LightMode" = "ShadowCaster"
            }
            ZWrite On
            ColorMask 0 // 阴影 Pass 只写深度，不输出颜色

            HLSLPROGRAM
            #pragma vertex shadowPassVert
            #pragma fragment shadowPassFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            // 支持点光源/聚光灯阴影投射（可选）
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            float3 _LightDirection;
            float3 _LightPosition;

            struct appdata
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
            };

            // 【核心】阴影偏移与裁剪
            // ApplyShadowBias: 沿光照方向偏移顶点，消除自阴影痤疮
            // ApplyShadowClamping: 防止偏移后顶点超出阴影贴图范围
            float4 GetShadowPositionHClip(float3 positionOS, float3 normalOS)
            {
                float3 positionWS = TransformObjectToWorld(positionOS);
                float3 normalWS = TransformObjectToWorldNormal(normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, lightDirectionWS)
                );
                positionCS = ApplyShadowClamping(positionCS);
                return positionCS;
            }

            v2f shadowPassVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = GetShadowPositionHClip(v.positionOS, v.normalOS);
                return o;
            }

            // 片元着色器返回 0，实际深度由 GPU 硬件自动写入
            float4 shadowPassFrag(v2f i) : SV_TARGET { return 0; }
            ENDHLSL
        }

        // ==================== Pass 2: 纯深度写入 ====================
        Pass
        {
            Tags
            {
                "LightMode" = "DepthOnly"
            }
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

            float depthOnlyFrag(v2f i) : SV_TARGET { return i.positionCS.z; }
            ENDHLSL
        }

        // ==================== Pass 3: 深度+法线编码 ====================
        Pass
        {
            Tags
            {
                "LightMode" = "DepthNormals"
            }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex depthNormalsVert
            #pragma fragment depthNormalsFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // 【注意】此 CBUFFER 与主 Pass 完全相同
            // SRP Batcher 要求所有 Pass 的 UnityPerMaterial 布局一致
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float _NormalStrength;
                float3 _AmbientLighting;
                float _Glossiness;
                float _FresnelPower;
                float _FresnelStrength;
            CBUFFER_END

            TEXTURE2D(_NormalTexture);
            SAMPLER(sampler_NormalTexture);

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 tangentWS : TEXCOORD2;
            };

            v2f depthNormalsVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.normalWS = NormalizeNormalPerVertex(normalWS);
                o.tangentWS = float4(TransformObjectToWorldDir(v.tangentOS.xyz), v.tangentOS.w);
                return o;
            }

            // 【关键】法线贴图必须在 DepthNormals Pass 中也应用
            // 否则 SSAO/SSR 等后处理读取的是未扰动的几何法线，产生视觉不一致
            float4 depthNormalsFrag(v2f i) : SV_TARGET
            {
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalTexture, sampler_NormalTexture, i.uv),
                    _NormalStrength
                );
                float3 binormalWS = cross(normalWS, i.tangentWS.xyz)
                    * i.tangentWS.w
                    * unity_WorldTransformParams.w;
                normalWS = normalize(
                    normalTS.x * i.tangentWS.xyz +
                    normalTS.y * binormalWS +
                    normalTS.z * normalWS
                );
                return float4(normalWS, 0.0f);
            }
            ENDHLSL
        }
    }
}