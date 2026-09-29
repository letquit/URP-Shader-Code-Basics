Shader "Basics/TessellatedWaves"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        _WaveHeight("Wave Height", Range(0.0, 1.0)) = 0.25
        _WaveSpeed("Wave Speed", Range(0.0, 10.0)) = 1.0
        
        // 细分强度：控制每条边最大细分数，值越大网格越密
        _TessellationAmount("Tessellation Amount", Range(1.0, 64.0)) = 1.0
        // 距离衰减起始：超过此距离开始降低细分等级
        _TessellationFadeStart("Tessellation Fade Start", Float) = 25
        // 距离衰减结束：超过此距离细分等级降为1（无细分）
        _TessellationFadeEnd("Tessellation Fade End", Float) = 50
        
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Source Blend Mode", Integer) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Destination Blend Mode", Integer) = 10
    }
 
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }
            
            Blend [_SrcBlend] [_DstBlend]
            ZWrite Off
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // 【关键】启用曲面细分编译指令
            // hull: 外壳着色器，负责传递控制点并调用 patch constant 函数
            // domain: 域着色器，在细分生成的新顶点上执行插值与位移
            #pragma hull hull
            #pragma domain domain

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float _WaveHeight;
                float _WaveSpeed;
                float _TessellationAmount;
                float _TessellationFadeStart;
                float _TessellationFadeEnd;
            CBUFFER_END

            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture);

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            // 细分控制点结构：在世界空间传递数据，避免模型矩阵重复计算
            struct tessControlPoint
            {
                float3 positionWS : INTERNALTESSPOS;
                float2 uv : TEXCOORD0;
            };

            // 细分因子输出结构：定义三角形三条边和内部的细分等级
            struct tessFactors
            {
                float edge[3] : SV_TessFactor;      // 三边细分等级 [1, 64]
                float inside : SV_InsideTessFactor; // 内部细分等级
            };

            struct t2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            // ==================== 顶点着色器 ====================
            // 仅做世界空间变换，不执行波浪位移
            // 位移延迟到 Domain Shader，确保细分后的新顶点也能正确波动
            tessControlPoint vert(appdata v)
            {
                tessControlPoint o = (tessControlPoint)0;
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                return o;
            }

            // ==================== 外壳着色器 ====================
            // 直通模式：直接将输入控制点传递给域着色器
            // 真正的细分逻辑在 patchConstantFunc 中执行
            [domain("tri")]                  // 三角形拓扑
            [outputcontrolpoints(3)]         // 输出3个控制点（三角形）
            [outputtopology("triangle_cw")]  // 顺时针绕序
            [partitioning("integer")]        // 整数分割，避免裂缝
            [patchconstantfunc("patchConstantFunc")] // 绑定 Patch Constant 函数
            tessControlPoint hull(InputPatch<tessControlPoint, 3> patch, uint id : SV_OutputControlPointID)
            {
                return patch[id];
            }

            // ==================== Patch Constant 函数 ====================
            // 【核心】基于摄像机距离的动态细分因子计算
            // 每个三角形补丁执行一次，而非每个顶点
            tessFactors patchConstantFunc(InputPatch<tessControlPoint, 3> patch)
            {
                tessFactors f = (tessFactors)0;

                // 计算三角形三条边的中点世界坐标
                float3 triPos0 = patch[0].positionWS;
                float3 triPos1 = patch[1].positionWS;
                float3 triPos2 = patch[2].positionWS;
                float3 edgePos0 = 0.5f * (triPos1 + triPos2);
                float3 edgePos1 = 0.5f * (triPos0 + triPos2);
                float3 edgePos2 = 0.5f * (triPos0 + triPos1);

                float3 camPos = _WorldSpaceCameraPos;

                // 各边中点到摄像机的距离
                float dist0 = distance(edgePos0, camPos);
                float dist1 = distance(edgePos1, camPos);
                float dist2 = distance(edgePos2, camPos);

                // 线性衰减：近距离全细分，远距离无细分，中间平滑过渡
                float fadeDist = _TessellationFadeEnd - _TessellationFadeStart;
                float edgeFactor0 = saturate(1.0f - (dist0 - _TessellationFadeStart) / fadeDist);
                float edgeFactor1 = saturate(1.0f - (dist1 - _TessellationFadeStart) / fadeDist);
                float edgeFactor2 = saturate(1.0f - (dist2 - _TessellationFadeStart) / fadeDist);

                // max(..., 1) 保证最小细分等级为1，避免退化三角形
                f.edge[0] = max(edgeFactor0 * _TessellationAmount, 1);
                f.edge[1] = max(edgeFactor1 * _TessellationAmount, 1);
                f.edge[2] = max(edgeFactor2 * _TessellationAmount, 1);

                // 内部细分取三边平均值，保证内外密度一致
                f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0f;
                
                return f;
            }

            // ==================== 域着色器 ====================
            // 【核心】在细分生成的新顶点上执行插值与波浪位移
            // barycentricCoordinates: 重心坐标，用于三个控制点的加权插值
            [domain("tri")]
            t2f domain(tessFactors factors, OutputPatch<tessControlPoint, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
            {
                t2f i = (t2f)0;

                // 重心坐标插值世界空间位置和UV
                float3 positionWS = patch[0].positionWS * barycentricCoordinates.x 
                                  + patch[1].positionWS * barycentricCoordinates.y 
                                  + patch[2].positionWS * barycentricCoordinates.z;
                float2 uv = patch[0].uv * barycentricCoordinates.x 
                          + patch[1].uv * barycentricCoordinates.y 
                          + patch[2].uv * barycentricCoordinates.z;

                // 【关键】波浪位移在此处执行，而非顶点着色器
                // 细分产生的新顶点同样参与波动，波形连续无锯齿
                float waveHeight = sin(positionWS.x + positionWS.z + _Time.y * _WaveSpeed) * _WaveHeight;
                float3 newPositionWS = float3(positionWS.x, positionWS.y + waveHeight, positionWS.z);

                i.positionCS = TransformWorldToHClip(newPositionWS);
                i.uv = uv;
                
                return i;
            }

            float4 frag(t2f i) : SV_TARGET
            {                
                float4 textureColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv);
                return textureColor * _BaseColor;
            }

            ENDHLSL
        }
    }
}