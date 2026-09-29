Shader "Basics/AdditionalLighting"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        _NormalTexture("Normal Texture", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0.0, 2.0)) = 1.0
        _AmbientLighting("Ambient Lighting", Color) = (0.2, 0.2, 0.2, 1)
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

        // ==================== Pass 0: 主光照 + 附加光照 ====================
        Pass
        {
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // 主光源阴影变体
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            
            // 【新增】光照 Cookie 支持（聚光灯/方向光的纹理遮罩）
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            
            // 【核心】附加光源编译指令
            // _ADDITIONAL_LIGHTS_VERTEX: 顶点级计算附加光（性能优先，精度低）
            // _ADDITIONAL_LIGHTS: 片元级计算附加光（质量优先，默认推荐）
            // 两者互斥，由 URP Asset 中的 Additional Lights 设置决定
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            
            // 附加光源阴影（仅当 URP Asset 开启 Additional Shadows 时生效）
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            
            // 【关键】Clustered Light Loop 支持
            // URP 14+ 引入的聚类光照剔除，替代传统逐光源遍历
            // 大幅减少无效光源计算，尤其适用于大量局部光源场景
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float _NormalStrength;
                float3 _AmbientLighting;
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
                float4 tangentOS : TANGENT;
                // 【新增】动态光照贴图 UV（用于 Shadow Mask 采样）
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
                // 传递到片元阶段用于 Shadow Mask 采样
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
                
                // 【新增】应用动态光照贴图的 Tiling/Offset 变换
                // unity_DynamicLightmapST 由 Lightmap 系统自动设置
                o.dynamicLightmapUV = v.dynamicLightmapUV.xy * unity_DynamicLightmapST.xy 
                                    + unity_DynamicLightmapST.zw;
                return o;
            }

            float4 frag(v2f i) : SV_TARGET
            {
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                float3 viewWS = normalize(i.viewWS);
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                
                // 【新增】采样 Shadow Mask 纹理
                // 存储烘焙光照的阴影信息，用于混合实时光与烘焙光的阴影过渡
                // 在 Mixed 光照模式下避免实时阴影与烘焙阴影的硬切换
                float4 shadowMask = SAMPLE_SHADOWMASK(i.dynamicLightmapUV);

                // ===== 法线贴图解码（同基础版）=====
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

                // ===== 主光源计算 =====
                Light mainLight = GetMainLight(shadowCoord);
                float3 mainLightColor = mainLight.distanceAttenuation 
                                      * mainLight.shadowAttenuation 
                                      * mainLight.color;

                float3 ambientLighting = SampleSH(normalWS);
                float3 diffuseLighting = saturate(dot(normalWS, mainLight.direction)) * mainLightColor;
                float3 reflectedVector = reflect(-mainLight.direction, normalWS);
                float3 specularLighting = pow(
                    saturate(dot(reflectedVector, viewWS)), 
                    pow(2.0f, _Glossiness)
                ) * mainLightColor;
                float3 fresnelLighting = pow(
                    1.0f - saturate(dot(normalWS, viewWS)), 
                    _FresnelPower
                ) * _FresnelStrength;

                // ===== 附加光源循环 =====
                // 【核心】仅在片元级附加光模式下编译此段代码
                #ifdef _ADDITIONAL_LIGHTS

                // 构建 InputData 供光照函数使用
                InputData inputData = (InputData)0;
                inputData.positionWS = i.positionWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);

                // 获取当前像素可见的附加光源数量
                // Cluster 模式下返回聚类剔除后的实际数量，非 Cluster 模式返回全局上限
                uint lightCount = GetAdditionalLightsCount();

                // 【关键】LIGHT_LOOP_BEGIN / LIGHT_LOOP_END 宏
                // 自动处理 Cluster 索引查找、光源类型分支、阴影采样等底层逻辑
                // 开发者只需关注单光源的光照计算，无需手动管理光源数组
                LIGHT_LOOP_BEGIN(lightCount)

                    // 获取第 lightIndex 个附加光源的完整信息
                    // shadowMask 传入以支持 Mixed 模式下的阴影混合
                    Light light = GetAdditionalLight(lightIndex, i.positionWS, shadowMask);
                    
                    float3 lightColor = light.distanceAttenuation 
                                      * light.shadowAttenuation 
                                      * light.color;

                    // 累加漫反射与镜面反射（菲涅尔通常仅对主光计算，避免多光源叠加过亮）
                    diffuseLighting += saturate(dot(normalWS, light.direction)) * lightColor;
                    reflectedVector = reflect(-light.direction, normalWS);
                    specularLighting += pow(
                        saturate(dot(reflectedVector, viewWS)), 
                        pow(2.0f, _Glossiness)
                    ) * lightColor;

                LIGHT_LOOP_END

                #endif

                // ===== 最终合成 =====
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv) * _BaseColor;
                float3 finalColor = (ambientLighting + diffuseLighting) * baseColor.rgb 
                                  + specularLighting 
                                  + fresnelLighting;
                return float4(finalColor, baseColor.a);
            }
            ENDHLSL
        }

        // ==================== Pass 1-3: 辅助 Pass（结构同基础版）====================
        // ShadowCaster / DepthOnly / DepthNormals 与 BasicLighting 完全一致
        // 此处省略重复注释，仅保留必要结构
        
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
                float3 _AmbientLighting; float _Glossiness; float _FresnelPower; float _FresnelStrength;
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