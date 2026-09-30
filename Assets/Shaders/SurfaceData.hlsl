#ifndef UNIVERSAL_SURFACE_DATA_INCLUDED
#define UNIVERSAL_SURFACE_DATA_INCLUDED

// 【关键】此结构体的字段顺序、类型、命名必须与 
// Universal ShaderGraph 的 Lit Master Node 输出引脚严格一致
// Shader Graph 生成的代码会直接按内存布局映射到此结构体
// 任何修改都会导致 Shader Graph 与手写代码之间的数据错位
struct SurfaceData
{
    half3 albedo;             // 基础颜色（漫反射反照率），线性空间 RGB
    half3 specular;           // 非金属材质的镜面反射颜色
    // 当 metallic > 0 时，实际镜面色由 lerp(specular, albedo, metallic) 计算
    half metallic;            // 金属度 [0,1]：0=绝缘体，1=导体
    // 控制 F0 反射率在 dielectric(0.04) 与 albedo 之间的插值权重
    half smoothness;          // 光滑度 [0,1]：0=完全粗糙，1=完美镜面
    // 内部转换为 roughness = 1 - smoothness 用于 GGX NDF 计算
    half3 normalTS;           // 切线空间法线偏移，范围 [-1,1]
    // (0,0,1) 表示无扰动；需经 TBN 矩阵变换至世界空间后参与光照
    half3 emission;           // 自发光颜色（HDR），线性空间 RGB
    // 直接叠加到最终输出，不受光照衰减影响
    half occlusion;           // 环境光遮蔽 [0,1]：0=全遮挡，1=无遮挡
    // 仅调制间接光照（GI + 环境反射），不影响直接光
    half alpha;               // 透明度 [0,1]
    // 具体行为取决于 Surface Type 设置（Opaque/Transparent/AlphaTest）
    half clearCoatMask;       // 清漆层遮罩 [0,1]：0=无清漆，1=完整清漆层
    // URP 双层材质模型：模拟车漆、塑料涂层等额外高光层
    half clearCoatSmoothness; // 清漆层光滑度 [0,1]
    // 独立于 base smoothness，允许底层粗糙而表层光滑
};

#endif