Shader "Basics/Waves"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        
        // 波浪振幅：控制波峰与波谷的高度差
        _WaveHeight("Wave Height", Range(0.0, 1.0)) = 0.25
        
        // 波浪频率/速度：值越大波动越快
        _WaveSpeed("Wave Speed", Range(0.0, 10.0)) = 1.0
        
        // 【标准透明混合】SrcAlpha + OneMinusSrcAlpha
        // 允许波浪呈现半透明水体效果，而非不透明贴片
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Source Blend Mode", Integer) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Destination Blend Mode", Integer) = 10
    }
 
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            // 透明队列确保在所有不透明物体之后绘制
            // 避免波浪遮挡后方几何体，同时保证深度排序正确
            "Queue" = "Transparent"
        }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }
            
            // 动态混合模式：支持运行时切换 Additive/Multiply 等效果
            Blend [_SrcBlend] [_DstBlend]
            
            // 【关键】关闭深度写入
            // 透明物体若写入深度，会导致后方透明片元被错误剔除
            // 波浪的起伏形态使深度写入问题更严重，必须禁用
            ZWrite Off
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float _WaveHeight;
                float _WaveSpeed;
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

                // 【核心】模型空间 → 世界空间变换
                // 波浪计算必须在世界空间进行，否则旋转/缩放物体会导致波形扭曲
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);

                // 【核心】正弦波顶点位移
                // positionWS.x + positionWS.z：沿对角线方向传播的平面波
                // _Time.y * _WaveSpeed：时间驱动相位偏移，实现动态波动
                // sin() 输出 [-1,1]，乘以 _WaveHeight 控制振幅范围
                float waveHeight = sin(positionWS.x + positionWS.z + _Time.y * _WaveSpeed) * _WaveHeight;
                
                // 仅修改 Y 轴（垂直方向），XZ 平面位置保持不变
                float3 newPositionWS = float3(positionWS.x, positionWS.y + waveHeight, positionWS.z);

                // 世界空间 → 裁剪空间变换
                // 注意：此处使用 TransformWorldToHClip 而非 TransformObjectToHClip
                // 因为顶点已在世界空间完成位移，不能再应用模型矩阵
                o.positionCS = TransformWorldToHClip(newPositionWS);
                
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
    }
}