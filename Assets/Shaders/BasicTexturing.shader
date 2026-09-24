Shader "Basics/BasicTexturing"
{
    // ==================== 材质属性声明区 ====================
    Properties
    {
        // 基础颜色：作为纹理的乘法因子，用于整体色调调整或染色
        _BaseColor("Base Color", Color) = (1,1,1,1)
        
        // 基础纹理：2D 贴图槽位，默认值为内置白色纹理
        // "white" {} 语法确保未指定贴图时采样返回纯白，避免黑色或错误
        _BaseTexture("Base Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            // 【注意】此处使用 "UniversalPipeline" 而非 "UniversalRenderPipeline"
            // 两者在 URP 中均被识别，但官方文档与模板推荐 "UniversalPipeline"
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            // Pass 命名：便于 Frame Debugger 中识别与调试
            Name "Unlit"
            
            // 【关键】LightMode 标签必须匹配 URP 渲染通道名称
            // "UniversalForward" 使此 Pass 被 URP 前向渲染路径正确调度
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // 指定最低着色器模型为 2.0，确保移动端与低端设备兼容
            #pragma target 2.0
            
            // 启用 GPU Instancing 变体编译
            // 允许相同材质的多个物体合批绘制，大幅降低 Draw Call
            #pragma multi_compile_instancing

            // 引入 URP 核心库：提供空间变换、纹理采样宏、实例化工具等
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // ==================== SRP Batcher 兼容常量缓冲 ====================
            // CBUFFER_START(UnityPerMaterial) 是 SRP Batcher 的硬性要求
            // 所有逐材质属性必须且仅能在此缓冲区内声明，否则 SRP Batcher 失效
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                // UV 平铺与偏移参数（Tiling & Offset）
                // _ST 后缀为 Unity 约定：xy = Tiling, zw = Offset
                float4 _BaseTexture_ST;
            CBUFFER_END

            // ==================== 纹理资源声明 ====================
            // URP 要求纹理与采样器分离声明，以支持采样器复用与跨平台兼容
            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture);

            // ==================== 顶点输入结构体 ====================
            struct appdata
            {
                float4 positionOS : POSITION;
                // 第一套 UV 坐标，TEXCOORD0 语义自动绑定网格 UV0 通道
                float2 uv : TEXCOORD0;
                
                // 【Instancing 必需】声明实例 ID 输入字段
                // GPU Instancing 时由引擎自动填充当前实例索引
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // ==================== 顶点→片元传递结构体 ====================
            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                
                // 【Instancing 必需】将实例 ID 从顶点阶段传递至片元阶段
                UNITY_VERTEX_INPUT_INSTANCE_ID
                
                // 【VR/立体渲染必需】初始化立体输出
                // 单目渲染时无开销，双目渲染时自动处理视图索引
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // ==================== 顶点着色器 ====================
            v2f vert(appdata v)
            {
                v2f o = (v2f)0;
                
                // 【Instancing 三步曲 - 步骤1】设置当前实例上下文
                // 后续矩阵变换与属性读取依赖此调用获取正确的实例数据
                UNITY_SETUP_INSTANCE_ID(v);
                
                // 【Instancing 三步曲 - 步骤2】将实例 ID 传递到输出结构体
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                
                // 【立体渲染】初始化片元阶段的立体输出索引
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                // 模型空间 → 裁剪空间变换（SRP Batcher 安全版本）
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                
                // UV 变换：应用材质面板中的 Tiling 和 Offset
                // 等价于 v.uv * _BaseTexture_ST.xy + _BaseTexture_ST.zw
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);

                return o;
            }

            // ==================== 片元着色器 ====================
            float4 frag(v2f i) : SV_TARGET
            {
                // 【Instancing 三步曲 - 步骤3】在片元阶段恢复实例上下文
                // 确保纹理采样与属性读取使用当前像素所属实例的数据
                UNITY_SETUP_INSTANCE_ID(i);
                
                // URP 标准纹理采样宏
                // 内部封装了平台差异处理，自动关联 TEXTURE2D 与 SAMPLER
                float4 textureColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv);
                
                // 纹理颜色 × 基色：实现染色、亮度调节与 Alpha 混合基础
                return textureColor * _BaseColor;
            }

            ENDHLSL
        }
    }
}