Shader "Basics/PBR"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        
        // 【关键】材质工作流切换开关
        // 启用时使用 Specular Setup（镜面反射颜色直接指定 F0）
        // 禁用时使用 Metallic Setup（metallic 插值 dielectric F0 与 albedo）
        [Toggle(_SPECULAR_SETUP)] _UseSpecularSetup("Use Specular Setup", Integer) = 0

        [NoScaleOffset] _MetallicMap("Metallic", 2D) = "white" {}
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0

        [NoScaleOffset] _SpecularMap("Specular Map", 2D) = "white" {}
        _SpecularColor("Specular Color", Color) = (0.2, 0.2, 0.2, 1.0)

        [NoScaleOffset] _SmoothnessMap("Smoothness Map", 2D) = "white" {}
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        
        // 【实用】支持从 Roughness 贴图自动转换为 Smoothness
        // 许多 Substance/Polyhaven 资产导出的是 Roughness，此选项避免手动反转
        [Toggle(_CONVERT_FROM_ROUGHNESS)] _ConvertFromRoughness("Convert From Roughness", Integer) = 0

        [NoScaleOffset] [Normal] _NormalTexture("Normal Texture", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0.0, 2.0)) = 1.0

        // 【关键】视差贴图强度，Range 上限 0.1 是经验安全值
        // 过大会导致 UV 偏移超出纹理边界产生拉伸伪影
        [NoScaleOffset] _HeightMap("Height Map", 2D) = "white" {}
        _HeightMapStrength("Height Map Strength", Range(0.0, 0.1)) = 0.0

        [NoScaleOffset] _OcclusionMap("Occlusion Map", 2D) = "white" {}
        _OcclusionStrength("Occlusion Strength", Range(0.0, 1.0)) = 1.0

        [NoScaleOffset] _EmissionMap("Emission Map", 2D) = "white" {}
        // HDR 标记允许自发光超过 1.0，用于 Bloom 后处理
        [HDR] _EmissionColor("Emission Color", Color) = (0.0, 0.0, 0.0, 1.0)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        // ==================== Pass 0: PBR 主光照 ====================
        Pass
        {
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // 标准 URP 光照变体编译
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP

            // 【关键】shader_feature_local vs multi_compile
            // local 关键字仅在材质实际使用时才生成变体，减少编译时间
            // multi_compile 会无条件生成所有组合，适用于全局开关
            #pragma shader_feature_local _ _CONVERT_FROM_ROUGHNESS
            #pragma shader_feature_local _ _SPECULAR_SETUP

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // 【新增】引入视差贴图库，提供 ParallaxMapping() 函数
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float _NormalStrength;
                float _Metallic;
                float3 _SpecularColor;
                float _Smoothness;
                float _HeightMapStrength;
                float _OcclusionStrength;
                float3 _EmissionColor;
            CBUFFER_END

            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture);

            // 【条件编译】根据工作流选择加载 Metallic 或 Specular 贴图
            // 未启用的贴图不会被采样，节省纹理单元和带宽
            #ifdef _SPECULAR_SETUP
            TEXTURE2D(_SpecularMap);
            SAMPLER(sampler_SpecularMap);
            #else
            TEXTURE2D(_MetallicMap);
            SAMPLER(sampler_MetallicMap);
            #endif

            TEXTURE2D(_SmoothnessMap);
            SAMPLER(sampler_SmoothnessMap);
            TEXTURE2D(_NormalTexture);
            SAMPLER(sampler_NormalTexture);
            TEXTURE2D(_HeightMap);
            SAMPLER(sampler_HeightMap);
            TEXTURE2D(_OcclusionMap);
            SAMPLER(sampler_OcclusionMap);
            TEXTURE2D(_EmissionMap);
            SAMPLER(sampler_EmissionMap);

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 dynamicLightmapUV : TEXCOORD2;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float3 viewWS : TEXCOORD3;
                float4 tangentWS : TEXCOORD4;
                float2 dynamicLightmapUV : TEXCOORD5;
            };

            v2f vert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.viewWS = GetWorldSpaceViewDir(o.positionWS);
                o.tangentWS = float4(TransformObjectToWorldDir(v.tangentOS.xyz), v.tangentOS.w);
                o.dynamicLightmapUV = v.dynamicLightmapUV.xy * unity_DynamicLightmapST.xy
                                    + unity_DynamicLightmapST.zw;
                return o;
            }

            float4 frag(v2f i) : SV_TARGET
            {
                float3 viewDirWS = normalize(i.viewWS);
                
                // 【核心】视差贴图：在切线空间中沿视线方向偏移 UV
                // 模拟表面凹凸的深度感，比法线贴图更有立体感但开销更高
                // 注意：此处直接修改了 i.uv，后续所有纹理采样都使用偏移后的 UV
                float3 viewDirTS = GetViewDirectionTangentSpace(i.tangentWS, i.normalWS, viewDirWS);
                i.uv += ParallaxMapping(
                    TEXTURE2D_ARGS(_HeightMap, sampler_HeightMap), 
                    viewDirTS, 
                    _HeightMapStrength, 
                    i.uv
                );

                // ===== 填充 SurfaceData =====
                SurfaceData surfaceData = (SurfaceData)0;

                float4 baseColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv) * _BaseColor;
                surfaceData.albedo = baseColor.rgb;
                surfaceData.alpha = baseColor.a;

                // 根据工作流分支填充 metallic/specular
                #ifdef _SPECULAR_SETUP
                    surfaceData.metallic = 0.0f;
                    surfaceData.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, i.uv).rgb 
                                         * _SpecularColor;
                #else
                    surfaceData.metallic = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, i.uv).r 
                                         * _Metallic;
                    surfaceData.specular = 0.0f;
                #endif

                // 可选的 Roughness → Smoothness 转换
                #ifdef _CONVERT_FROM_ROUGHNESS
                    surfaceData.smoothness = (1.0f - SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_SmoothnessMap, i.uv).r) 
                                           * _Smoothness;
                #else
                    surfaceData.smoothness = SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_SmoothnessMap, i.uv).r 
                                           * _Smoothness;
                #endif

                // 法线贴图解码与归一化
                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalTexture, sampler_NormalTexture, i.uv), 
                    _NormalStrength
                );
                surfaceData.normalTS = normalize(normalTS);
                
                // 自发光（HDR 值可直接 >1.0）
                surfaceData.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.uv).rgb 
                                     * _EmissionColor;
                
                // ⚠️ 注意：本例未填充 surfaceData.occlusion
                // 若需 AO 效果，应添加：
                // surfaceData.occlusion = lerp(1.0, SAMPLE_TEXTURE2D(...).g, _OcclusionStrength);

                // ===== 填充 InputData =====
                InputData inputData = (InputData)0;
                inputData.positionCS = i.positionCS;
                inputData.positionWS = i.positionWS;

                // 构建 TBN 矩阵用于切线→世界空间变换
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                float3 bitangent = cross(normalWS.xyz, i.tangentWS.xyz) 
                                 * i.tangentWS.w 
                                 * unity_WorldTransformParams.w;
                inputData.tangentToWorld = float3x3(i.tangentWS.xyz, bitangent.xyz, normalWS.xyz);

                // 将切线空间法线变换到世界空间
                inputData.normalWS = TransformTangentToWorld(surfaceData.normalTS, inputData.tangentToWorld);
                inputData.viewDirectionWS = viewDirWS;
                inputData.shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(i.dynamicLightmapUV);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);

                // 【核心】调用 URP 内置 PBR 光照函数
                // 内部完成 GGX NDF + Smith G + Schlick F + GI + 附加光 + 阴影等全部计算
                return UniversalFragmentPBR(inputData, surfaceData);
            }
            ENDHLSL
        }

        // ==================== Pass 1-3: 辅助 Pass ====================
        // ShadowCaster / DepthOnly / DepthNormals 结构与 BasicLighting 一致
        // DepthNormals 中同步应用了法线贴图以确保 SSAO/SSR 一致性
        
        Pass
        {
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ColorMask 0
            HLSLPROGRAM
            #pragma vertex shadowPassVert
            #pragma fragment shadowPassFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            float3 _LightDirection;
            float3 _LightPosition;
            struct appdata { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct v2f { float4 positionCS : SV_POSITION; };
            float4 GetShadowPositionHClip(float3 positionOS, float3 normalOS)
            {
                float3 positionWS = TransformObjectToWorld(positionOS);
                float3 normalWS = TransformObjectToWorldNormal(normalOS);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                float3 lightDirectionWS = _LightDirection;
                #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
                positionCS = ApplyShadowClamping(positionCS);
                return positionCS;
            }
            v2f shadowPassVert(appdata v) { v2f o = (v2f)0; o.positionCS = GetShadowPositionHClip(v.positionOS, v.normalOS); return o; }
            float4 shadowPassFrag(v2f i) : SV_TARGET { return 0; }
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
            struct appdata { float4 positionOS : POSITION; };
            struct v2f { float4 positionCS : SV_POSITION; };
            v2f depthOnlyVert(appdata v) { v2f o = (v2f)0; o.positionCS = TransformObjectToHClip(v.positionOS.xyz); return o; }
            float depthOnlyFrag(v2f i) : SV_TARGET { return i.positionCS.z; }
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
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor; float4 _BaseTexture_ST; float _NormalStrength;
                float _Metallic; float3 _SpecularColor; float _Smoothness;
                float _HeightMapStrength; float _OcclusionStrength; float3 _EmissionColor;
            CBUFFER_END
            TEXTURE2D(_NormalTexture); SAMPLER(sampler_NormalTexture);
            struct appdata { float4 positionOS : POSITION; float2 uv : TEXCOORD0; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; };
            struct v2f { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; float4 tangentWS : TEXCOORD2; };
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
            float4 depthNormalsFrag(v2f i) : SV_TARGET
            {
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalTexture, sampler_NormalTexture, i.uv), _NormalStrength);
                float3 binormalWS = cross(normalWS, i.tangentWS.xyz) * i.tangentWS.w * unity_WorldTransformParams.w;
                normalWS = normalize(normalTS.x * i.tangentWS.xyz + normalTS.y * binormalWS + normalTS.z * normalWS);
                return float4(normalWS, 0.0f);
            }
            ENDHLSL
        }
    }
}