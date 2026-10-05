using System;
using UnityEngine;
using UnityEngine.Rendering;

// 注册到 Volume Override 菜单："Basics/Outline"
// [Serializable] 确保参数可序列化到 Volume Profile 资产中
[Serializable, VolumeComponentMenu("Basics/Outline")]
public class OutlineSettings : VolumeComponent, IPostProcessComponent
{
    // ===== 参数声明 =====

    // 描边强度 / 混合系数
    // ClampedFloatParameter 确保 Volume 混合时值始终在 [0, 1] 范围内
    // 【关键】0.0f 作为默认值兼作"关闭"语义，无需额外 BoolParameter
    public ClampedFloatParameter strength = new(0.0f, 0.0f, 1.0f);

    // 描边颜色
    // ColorParameter 支持 HDR、Alpha 通道和 Volume 间的平滑颜色插值
    public ColorParameter outlineColor = new(Color.black);

    // 颜色差异阈值：控制哪些像素被判定为"边缘"
    // 值越高 → 仅高对比度区域显示描边（粗犷、选择性）
    // 值越低 → 微小颜色变化也触发描边（细腻、噪点多）
    // Clamp [0, 1] 防止非法阈值导致边缘检测完全失效或全屏误判
    public ClampedFloatParameter colorThreshold = new(0.9f, 0.0f, 1.0f);

    /// <summary>
    /// IPostProcessComponent 接口实现
    /// 渲染管线每帧调用此方法决定是否执行对应 Pass
    /// </summary>
    /// <returns>
    /// true = 入队渲染 Pass；false = 跳过（零 GPU 开销）
    /// </returns>
    /// <remarks>
    /// 采用隐式激活模式：strength == 0 时效果不可见，等价于关闭
    /// 相比 SilhouetteSettings 的显式 enabled 开关，此模式更简洁
    /// 适用于存在明确"无效值/零值"语义的参数驱动型效果
    /// </remarks>
    public bool IsActive()
    {
        return strength.value > 0.0f && active;
    }
}