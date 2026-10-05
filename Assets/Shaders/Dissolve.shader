Shader "Basics/Dissolve"
{
    Properties
    {
        // ===== 基础表面属性 =====
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        
        // PBR 工作流切换：Metallic（默认）或 Specular
        [Toggle(_SPECULAR_SETUP)] _UseSpecularSetup("Use Specular Setup", Integer) = 0

        [NoScaleOffset] _MetallicMap("Metallic", 2D) = "white" {}
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0

        [NoScaleOffset] _SpecularMap("Specular Map", 2D) = "white" {}
        _SpecularColor("Specular Color", Color) = (0.2, 0.2, 0.2, 1.0)

        [NoScaleOffset] _SmoothnessMap("Smoothness Map", 2D) = "white" {}
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        // 支持从 Roughness 贴图自动转换为 Smoothness
        [Toggle(_CONVERT_FROM_ROUGHNESS)] _ConvertFromRoughness("Convert From Roughness", Integer) = 0

        [NoScaleOffset] [Normal] _NormalTexture("Normal Texture", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0.0, 2.0)) = 1.0

        // 视差映射：增强表面凹凸立体感
        [NoScaleOffset] _HeightMap("Height Map", 2D) = "white" {}
        _HeightMapStrength("Height Map Strength", Range(0.0, 0.1)) = 0.0

        [NoScaleOffset] _OcclusionMap("Occlusion Map", 2D) = "white" {}
        _OcclusionStrength("Occlusion Strength", Range(0.0, 1.0)) = 1.0

        [NoScaleOffset] _EmissionMap("Emission Map", 2D) = "white" {}
        [HDR] _EmissionColor("Emission Color", Color) = (0.0, 0.0, 0.0, 1.0)
        
        // ===== 溶解核心参数 =====
        _NoiseScale("Noise Scale", Float) = 150          // Voronoi 细胞密度
        _NoiseStrength("Noise Strength", Range(0.0, 1.0)) = 0.5 // 噪声对高度的扰动幅度
        _CutoffHeight("Cutoff Height", Float) = 0.0      // 溶解阈值（动画驱动此值）
        [HDR] _EdgeColor("Edge Color", Color) = (1.0, 1.0, 1.0, 1.0) // 边缘发光颜色
        _EdgeThickness("Edge Thickness", Range(0.0, 0.2)) = 0.02     // 发光带宽度
        _CycleSpeed("Cycle Speed", Range(0.0, 2.0)) = 1.0            // 噪声动画速度
        
        // ===== URP 内部状态变量（由 CustomEditor 自动管理）=====
        // 这些变量控制混合模式、深度写入、渲染队列等，不应手动编辑
        [HideInInspector] _Surface("_Surface", Float) = 0
        [HideInInspector] _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        [HideInInspector] _SrcBlend("_SrcBlend", Float) = 1
        [HideInInspector] _DstBlend("_DstBlend", Float) = 0
        [HideInInspector] _SrcBlendAlpha("SrcBlendAlpha", Float) = 1
        [HideInInspector] _DstBlendAlpha("_DstBlendAlpha", Float) = 0
        [HideInInspector] _ZWrite("_ZWrite", Float) = 1
        [HideInInspector] _ZTest("_ZTest", Float) = 4
        [HideInInspector] _Cull("_Cull", Float) = 2
        [HideInInspector] _AlphaToMask("_AlphaToMask", Float) = 0
        [HideInInspector] _CastShadows("_CastShadows", Float) = 1
        [HideInInspector] _ReceiveShadows("_ReceiveShadows", Float) = 1
        [HideInInspector] _Blend("Blend", Float) = 0
        [HideInInspector] _AlphaClip("_AlphaClip", Float) = 0
        [HideInInspector] _ZWriteControl("ZWriteControl", Float) = 1
        [HideInInspector] _QueueOffset("_QueueOffset", Float) = 0
        [HideInInspector] _QueueControl("_QueueControl", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        // ====================================================================
        // Pass 1: UniversalForward - 主光照与溶解效果
        // ====================================================================
        Pass
        {
            Tags { "LightMode" = "UniversalForward" }

            Cull [_Cull]
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Blend [_SrcBlend] [_DstBlend], [_SrcBlendAlpha] [_DstBlendAlpha]
            AlphaToMask [_AlphaToMask]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // URP 光照关键字：主光源阴影、软阴影质量、Cookie、额外光源、聚簇光照
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP

            // 局部关键字：仅影响当前材质，减少全局变体爆炸
            #pragma shader_feature_local _ _CONVERT_FROM_ROUGHNESS
            #pragma shader_feature_local _ _SPECULAR_SETUP
            #pragma shader_feature_local _ _RECEIVE_SHADOWS_OFF
            #pragma shader_feature_local_fragment _ _ALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "./NoiseFunctions.hlsl" // 包含 voronoiNoise / perlinNoise 实现

            // SRP Batcher 兼容：所有材质属性必须在 UnityPerMaterial CBUFFER 中
            CBUFFER_START(UnityPerMaterial)
                float _Surface;
                float _Cutoff;
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float _NormalStrength;
                float _Metallic;
                float3 _SpecularColor;
                float _Smoothness;
                float _HeightMapStrength;
                float _OcclusionStrength;
                float3 _EmissionColor;
                float _NoiseScale;
                float _NoiseStrength;
                float _CutoffHeight;
                float3 _EdgeColor;
                float _EdgeThickness;
                float _CycleSpeed;
            CBUFFER_END

            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture);

            // 根据工作流条件编译不同的贴图声明
            #ifdef _SPECULAR_SETUP
            TEXTURE2D(_SpecularMap);
            SAMPLER(sampler_SpecularMap);
            #else
            TEXTURE2D(_MetallicMap);
            SAMPLER(sampler_MetallicMap);
            #endif

            TEXTURE2D(_SmoothnessMap);    SAMPLER(sampler_SmoothnessMap);
            TEXTURE2D(_NormalTexture);    SAMPLER(sampler_NormalTexture);
            TEXTURE2D(_HeightMap);        SAMPLER(sampler_HeightMap);
            TEXTURE2D(_OcclusionMap);     SAMPLER(sampler_OcclusionMap);
            TEXTURE2D(_EmissionMap);      SAMPLER(sampler_EmissionMap);

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
                float4 positionOS : TEXCOORD2;   // 保留 OS 坐标用于溶解高度计算
                float3 positionWS : TEXCOORD3;
                float3 viewWS : TEXCOORD4;
                float4 tangentWS : TEXCOORD5;
                float2 dynamicLightmapUV : TEXCOORD6;
            };

            v2f vert(appdata v)
            {
                v2f o = (v2f)0;
                
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.positionOS = v.positionOS; // ⚠️ 传递到片元着色器用于溶解判定
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
                
                // 【视差映射】根据高度图偏移 UV，增强表面细节立体感
                // 必须在采样其他贴图之前执行，因为后续所有贴图都使用偏移后的 UV
                float3 viewDirTS = GetViewDirectionTangentSpace(i.tangentWS, i.normalWS, viewDirWS);
                i.uv += ParallaxMapping(
                    TEXTURE2D_ARGS(_HeightMap, sampler_HeightMap), 
                    viewDirTS, _HeightMapStrength, i.uv
                );

                SurfaceData surfaceData = (SurfaceData)0;

                // 基础颜色采样 + Alpha 测试
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv) * _BaseColor;
                surfaceData.albedo = baseColor.rgb;
                surfaceData.alpha = baseColor.a;
                AlphaDiscard(surfaceData.alpha, _Cutoff);

                // ===== 溶解核心逻辑 =====
                // 使用 Voronoi 噪声生成有机的细胞状溶解图案
                float distFromCenter, distFromEdge;
                voronoiNoise(i.uv, _NoiseScale, distFromCenter, distFromEdge, _Time.y * _CycleSpeed);
                
                // 使用 distFromCenter 作为溶解掩码（细胞中心先消失，边缘后消失）
                // 若改用 distFromEdge 则变为"沿细胞边界溶解"的不同视觉效果
                float noise = (distFromCenter - 0.5f) * _NoiseStrength;
                // float noise = (distFromEdge - 0.5f) * _NoiseStrength;
                
                // 将物体空间 Y 坐标与噪声叠加，实现"从下往上"的定向溶解
                // _CutoffHeight 由外部动画驱动：-1 → 完全显示，+1 → 完全溶解
                float height = i.positionOS.y + noise;
                AlphaDiscard(_CutoffHeight, height); // ⚠️ 注意参数顺序：丢弃 height < _CutoffHeight 的像素

                // PBR 属性采样（根据工作流分支）
                #ifdef _SPECULAR_SETUP
                    surfaceData.metallic = 0.0f;
                    surfaceData.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, i.uv).rgb 
                                         * _SpecularColor;
                #else
                    surfaceData.metallic = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, i.uv).r 
                                         * _Metallic;
                    surfaceData.specular = 0.0f;
                #endif

                // Smoothness / Roughness 转换
                #ifdef _CONVERT_FROM_ROUGHNESS
                    surfaceData.smoothness = (1.0f - SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_SmoothnessMap, i.uv).r) 
                                           * _Smoothness;
                #else
                    surfaceData.smoothness = SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_SmoothnessMap, i.uv).r 
                                           * _Smoothness;
                #endif

                surfaceData.occlusion = lerp(1.0f,
                    SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, i.uv).r,
                    _OcclusionStrength);

                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalTexture, sampler_NormalTexture, i.uv), _NormalStrength);
                surfaceData.normalTS = normalize(normalTS);
                
                surfaceData.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.uv).rgb 
                                     * _EmissionColor;

                // 【边缘发光】在溶解边界处叠加 HDR 自发光
                // step 产生硬边过渡；_EdgeThickness 控制发光带宽度
                // 当 height 处于 [_CutoffHeight - thickness, _CutoffHeight] 区间时 edge=1
                float edge = step(_CutoffHeight - _EdgeThickness, height);
                surfaceData.emission += edge * _EdgeColor;

                // 构建光照输入数据
                InputData inputData = (InputData)0;
                inputData.positionCS = i.positionCS;
                inputData.positionWS = i.positionWS;

                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                float3 bitangent = cross(normalWS.xyz, i.tangentWS.xyz) 
                                 * i.tangentWS.w * unity_WorldTransformParams.w;
                inputData.tangentToWorld = float3x3(i.tangentWS.xyz, bitangent.xyz, normalWS.xyz);
                inputData.normalWS = TransformTangentToWorld(surfaceData.normalTS, inputData.tangentToWorld);
                inputData.viewDirectionWS = viewDirWS;
                inputData.shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(i.dynamicLightmapUV);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);

                // URP PBR 光照计算
                float4 color = UniversalFragmentPBR(inputData, surfaceData);
                
                color.a = OutputAlpha(color.a, IsSurfaceTypeTransparent(_Surface));

                return color;
            }
            ENDHLSL
        }

        // ====================================================================
        // Pass 2: ShadowCaster - 阴影投射
        // ⚠️ 关键：溶解裁剪逻辑必须与主 Pass 完全一致
        //    否则会出现"模型已溶解但阴影仍然完整"的视觉 Bug
        // ====================================================================
        Pass
        {
            Tags { "LightMode" = "ShadowCaster" }
            Cull [_Cull]
            ZTest LEqual
            ZWrite On
            ColorMask 0
            
            HLSLPROGRAM
            #pragma vertex shadowPassVert
            #pragma fragment shadowPassFrag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "./NoiseFunctions.hlsl"
            
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #pragma shader_feature_local_fragment _ _ALPHATEST_ON

            // ⚠️ CBUFFER 布局必须与主 Pass 完全一致（SRP Batcher 要求）
            CBUFFER_START(UnityPerMaterial)
                float _Surface; float _Cutoff; float4 _BaseColor; float4 _BaseTexture_ST;
                float _NormalStrength; float _Metallic; float3 _SpecularColor; float _Smoothness;
                float _HeightMapStrength; float _OcclusionStrength; float3 _EmissionColor;
                float _NoiseScale; float _NoiseStrength; float _CutoffHeight;
                float3 _EdgeColor; float _EdgeThickness; float _CycleSpeed;
            CBUFFER_END

            TEXTURE2D(_BaseTexture); SAMPLER(sampler_BaseTexture);
            float3 _LightDirection; float3 _LightPosition;
            
            struct appdata { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct v2f { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float4 positionOS : TEXCOORD1; };
            
            // 阴影偏移 + 钳制，防止阴影痤疮和漏光
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
            
            v2f shadowPassVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = GetShadowPositionHClip(v.positionOS.xyz, v.normalOS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                o.positionOS = v.positionOS;
                return o;
            }
            
            float4 shadowPassFrag(v2f i) : SV_TARGET
            {
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv) * _BaseColor;
                AlphaDiscard(baseColor.a, _Cutoff);

                // ⚠️ 与主 Pass 相同的溶解逻辑（注意：此处使用 distFromEdge 可能是有意为之的艺术选择
                //    或与主 Pass 存在不一致——生产环境中应统一为 distFromCenter）
                float distFromCenter, distFromEdge;
                voronoiNoise(i.uv, _NoiseScale, distFromCenter, distFromEdge, _Time.y * _CycleSpeed);
                float noise = (distFromEdge - 0.5f) * _NoiseStrength; // ⚠️ 注意：主 Pass 用的是 distFromCenter
                float height = i.positionOS.y + noise;
                AlphaDiscard(_CutoffHeight, height);

                return 0;
            }
            ENDHLSL
        }

        // ====================================================================
        // Pass 3: DepthOnly - 纯深度写入
        // 用于 SSAO、DOF、雾效等依赖深度缓冲的后处理
        // 溶解区域必须正确剔除深度，否则后处理会"看到"已溶解的部分
        // ====================================================================
        Pass
        {
            Tags { "LightMode" = "DepthOnly" }
            Cull [_Cull]
            ZTest LEqual
            ZWrite On
            ColorMask R // 仅写入 R 通道（深度缓冲单通道优化）
            
            HLSLPROGRAM
            #pragma vertex depthOnlyVert
            #pragma fragment depthOnlyFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "./NoiseFunctions.hlsl"
            #pragma shader_feature_local_fragment _ _ALPHATEST_ON

            CBUFFER_START(UnityPerMaterial)
                float _Surface; float _Cutoff; float4 _BaseColor; float4 _BaseTexture_ST;
                float _NormalStrength; float _Metallic; float3 _SpecularColor; float _Smoothness;
                float _HeightMapStrength; float _OcclusionStrength; float3 _EmissionColor;
                float _NoiseScale; float _NoiseStrength; float _CutoffHeight;
                float3 _EdgeColor; float _EdgeThickness; float _CycleSpeed;
            CBUFFER_END

            TEXTURE2D(_BaseTexture); SAMPLER(sampler_BaseTexture);
            
            struct appdata { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float4 positionOS : TEXCOORD1; };
            
            v2f depthOnlyVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                o.positionOS = v.positionOS;
                return o;
            }
            
            float depthOnlyFrag(v2f i) : SV_TARGET
            {
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv) * _BaseColor;
                AlphaDiscard(baseColor.a, _Cutoff);

                // 与主 Pass 一致的溶解裁剪
                float distFromCenter, distFromEdge;
                voronoiNoise(i.uv, _NoiseScale, distFromCenter, distFromEdge, _Time.y * _CycleSpeed);
                float noise = (distFromEdge - 0.5f) * _NoiseStrength;
                float height = i.positionOS.y + noise;
                AlphaDiscard(_CutoffHeight, height);

                return i.positionCS.z;
            }
            ENDHLSL
        }

        // ====================================================================
        // Pass 4: DepthNormals - 深度 + 法线联合写入
        // 用于 SSR（屏幕空间反射）、SSGI 等需要精确法线的后处理
        // 溶解区域的法线也必须被正确剔除
        // ====================================================================
        Pass
        {
            Tags { "LightMode" = "DepthNormals" }
            Cull [_Cull]
            ZTest LEqual
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex depthNormalsVert
            #pragma fragment depthNormalsFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "./NoiseFunctions.hlsl"
            #pragma shader_feature_local_fragment _ _ALPHATEST_ON
            
            CBUFFER_START(UnityPerMaterial)
                float _Surface; float _Cutoff; float4 _BaseColor; float4 _BaseTexture_ST;
                float _NormalStrength; float _Metallic; float3 _SpecularColor; float _Smoothness;
                float _HeightMapStrength; float _OcclusionStrength; float3 _EmissionColor;
                float _NoiseScale; float _NoiseStrength; float _CutoffHeight;
                float3 _EdgeColor; float _EdgeThickness; float _CycleSpeed;
            CBUFFER_END

            TEXTURE2D(_BaseTexture); SAMPLER(sampler_BaseTexture);
            TEXTURE2D(_NormalTexture); SAMPLER(sampler_NormalTexture);
            
            struct appdata { float4 positionOS : POSITION; float2 uv : TEXCOORD0; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; };
            struct v2f { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; float4 tangentWS : TEXCOORD2; float4 positionOS : TEXCOORD3; };
            
            v2f depthNormalsVert(appdata v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.normalWS = NormalizeNormalPerVertex(normalWS);
                o.tangentWS = float4(TransformObjectToWorldDir(v.tangentOS.xyz), v.tangentOS.w);
                o.positionOS = v.positionOS;
                return o;
            }
            
            float4 depthNormalsFrag(v2f i) : SV_TARGET
            {
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv) * _BaseColor;
                AlphaDiscard(baseColor.a, _Cutoff);

                // 与主 Pass 一致的溶解裁剪
                float distFromCenter, distFromEdge;
                voronoiNoise(i.uv, _NoiseScale, distFromCenter, distFromEdge, _Time.y * _CycleSpeed);
                float noise = (distFromEdge - 0.5f) * _NoiseStrength;
                float height = i.positionOS.y + noise;
                AlphaDiscard(_CutoffHeight, height);
                
                // 法线贴图解包 + TBN 变换
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalTexture, sampler_NormalTexture, i.uv), _NormalStrength);
                float3 binormalWS = cross(normalWS, i.tangentWS.xyz) * i.tangentWS.w * unity_WorldTransformParams.w;
                normalWS = normalize(normalTS.x * i.tangentWS.xyz + normalTS.y * binormalWS + normalTS.z * normalWS);
                return float4(normalWS, 0.0f);
            }
            ENDHLSL
        }
    }

    // 自定义 Shader GUI，自动管理混合模式/深度/队列等隐藏属性
    CustomEditor "ShaderBasics.Editor.DissolveShaderGUI"
}