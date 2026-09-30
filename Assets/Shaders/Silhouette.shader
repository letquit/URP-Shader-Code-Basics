Shader "Basics/Silhouette"
{
    Properties
    {
        // 前景色：当物体被其他物体遮挡（深度较近）时显示的颜色
        _ForegroundColor("Foreground Color", Color) = (0, 0, 0, 0)
        // 背景色：当物体未被遮挡（深度较远/可见）时显示的颜色
        _BackgroundColor("Background Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            // Transparent 队列确保在所有不透明物体绘制完成后执行
            // 此时场景深度缓冲已填充完毕，SampleSceneDepth 才能读取有效数据
            "Queue" = "Transparent"
        }

        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // 【关键】引入深度纹理声明库
            // 提供 SampleSceneDepth() 函数及 _CameraDepthTexture 资源绑定
            // URP 不会自动包含此头文件，必须显式引入才能访问场景深度
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _ForegroundColor;
                float4 _BackgroundColor;
            CBUFFER_END

            struct appdata
            {
                float4 positionOS : POSITION;
                // 无需 UV、法线等属性，剪影效果仅依赖空间位置与深度
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                // 存储齐次屏幕坐标，用于片元阶段计算归一化屏幕 UV
                float4 positionSS : TEXCOORD0;
            };

            v2f vert(appdata v)
            {
                v2f o = (v2f)0;

                // 模型空间 → 裁剪空间变换
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);

                // 【核心】计算齐次屏幕坐标
                // 返回值为 (x*w, y*w, z*w, w)，其中 xy/w 即归一化屏幕 UV [0,1]
                // 必须在顶点阶段计算并传递，避免片元阶段重复投影运算
                o.positionSS = ComputeScreenPos(o.positionCS);

                return o;
            }

            float4 frag(v2f i) : SV_TARGET
            {
                // 透视除法：将齐次坐标转换为归一化屏幕 UV
                // i.positionSS.w 在光栅化阶段已被插值，此处除法是安全的
                float2 screenUV = i.positionSS.xy / i.positionSS.w;

                // 【核心】采样场景深度缓冲
                // 返回原始非线性深度值（0=近裁剪面, 1=远裁剪面）
                // 该值来自之前不透明 Pass 写入的深度缓冲，不包含当前透明物体自身
                float rawDepth = SampleSceneDepth(screenUV);

                // 【关键】将非线性深度转换为线性 [0,1] 深度
                // _ZBufferParams 由 URP 自动上传，包含近/远裁剪面信息
                // 线性深度使颜色插值在视觉上均匀分布，避免近处压缩远处拉伸
                float linearDepth = Linear01Depth(rawDepth, _ZBufferParams);

                // 根据线性深度在前景色与背景色之间插值
                // depth=0 (最近) → 纯前景色；depth=1 (最远) → 纯背景色
                // 中间深度产生平滑过渡，形成自然的剪影渐变效果
                return lerp(_ForegroundColor, _BackgroundColor, linearDepth);
            }
            ENDHLSL
        }
    }
}