// 定义 Shader 在 Unity 编辑器材质面板中的显示路径与名称
Shader "Basics/HelloWorld"
{
    // ==================== 材质属性声明区 ====================
    // 此处定义的变量会自动暴露为材质 Inspector 面板中的可调参数
    Properties
    {
        // 声明基础颜色属性，默认值为纯白不透明
        // 语法：_变量名("面板显示名", 类型) = 默认值
        _BaseColor("Base Color", Color) = (1,1,1,1)
    }

    // ==================== 子着色器块 ====================
    // SubShader 是 GPU 执行的实际渲染程序容器
    SubShader
    {
        // ==================== 渲染标签配置 ====================
        // Tags 告知 URP 渲染管线如何分类、排序和处理此 Shader
        Tags
        {
            // 【关键】声明此 Shader 专用于 Universal Render Pipeline
            // URP 仅识别带有此标签的 SubShader，缺失则回退到内置管线或紫色错误材质
            "RenderPipeline" = "UniversalRenderPipeline"

            // 标识渲染类型为不透明物体
            // URP 根据此标签决定何时调用该 Shader（如 Opaque 阶段而非 Transparent 阶段）
            "RenderType" = "Opaque"

            // 指定渲染队列顺序
            // Geometry(2000) 为标准不透明物体队列，确保在天空盒之后、透明物体之前绘制
            "Queue" = "Geometry"
        }
        
        // ==================== 渲染通道 ====================
        // Pass 定义单次完整的绘制调用，一个 SubShader 可包含多个 Pass
        Pass
        {
            // 标记 HLSL 代码块起始，URP 统一使用 HLSL 语言（取代旧版 CG）
            HLSLPROGRAM

            // 编译指令：指定顶点着色器入口函数名为 vert
            #pragma vertex vert
            // 编译指令：指定片元着色器入口函数名为 frag
            #pragma fragment frag

            // 引入 URP 核心库，提供空间变换、颜色处理等基础工具函数
            // 这是 URP Shader 区别于 Built-in 管线的核心依赖
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // 声明与 Properties 中同名的全局变量，接收 CPU 端传入的材质参数
            float4 _BaseColor;

            // ==================== 顶点输入结构体 ====================
            // 描述从网格缓冲区传入顶点着色器的数据布局
            struct appdata
            {
                // 模型空间顶点位置，POSITION 语义绑定自动填充顶点缓冲中的坐标数据
                float4 positionOS : POSITION;
            };

            // ==================== 顶点→片元传递结构体 ====================
            // 定义顶点着色器输出、经光栅化插值后传入片元着色器的数据
            struct v2f
            {
                // 齐次裁剪空间位置，SV_POSITION 为系统必需语义
                // GPU 依赖此值进行裁剪、透视除法与屏幕映射
                float4 positionCS : SV_POSITION;
            };

            // ==================== 顶点着色器 ====================
            // 职责：将每个顶点从模型空间变换至裁剪空间
            v2f vert(appdata v)
            {
                // 初始化输出结构体为零值，避免未赋值字段产生不确定结果
                v2f o = (v2f)0;

                // 【核心变换】模型空间(Object) → 裁剪空间(HClip)
                // 内部封装了 UNITY_MATRIX_MVP 矩阵乘法，是 URP 推荐的标准变换方式
                // 等价于 mul(UNITY_MATRIX_VP, mul(UNITY_MATRIX_M, float4(v.positionOS.xyz, 1.0)))
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);

                return o;
            }

            // ==================== 片元着色器 ====================
            // 职责：计算每个像素的最终输出颜色
            // SV_TARGET 语义指定输出绑定到帧缓冲的颜色附件
            float4 frag(v2f i) : SV_TARGET
            {
                // 直接返回材质面板配置的基色，无光照、无纹理、无特效
                // 作为 Hello World 示例，验证 Shader 编译、数据传递与渲染管线集成是否正常
                return _BaseColor;
            }
            
            // 标记 HLSL 代码块结束
            ENDHLSL
        }
    }
}