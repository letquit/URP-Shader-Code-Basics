using System;
using UnityEngine;
using UnityEngine.Rendering;

// 注册到 Volume Override 菜单："Basics/Silhouette"
// [Serializable] 确保参数可序列化到 Volume Profile 资产中
[Serializable, VolumeComponentMenu("Basics/Silhouette")]
public class SilhouetteSettings : VolumeComponent, IPostProcessComponent
{
    // ===== 参数声明 =====
    
    // 【关键】显式启用开关
    // 区别于仅靠参数值隐式判断（如 strength > 0）
    // 当所有参数都有合法非零默认值时，必须使用 BoolParameter 作为激活条件
    public BoolParameter enabled = new(false);
    
    // 近处颜色：深度值接近 0 时的输出颜色
    // ColorParameter 支持 HDR 拾色器、Alpha 通道和 Volume 混合插值
    public ColorParameter nearColor = new(Color.black);
    
    // 远处颜色：深度值接近 1 时的输出颜色
    public ColorParameter farColor = new(Color.white);
    
    // 深度幂次曲线控制
    // ClampedFloatParameter 确保 Volume 混合时不会超出 [0, 10] 范围
    // power=1: 线性过渡 | power<1: 近处占比更大 | power>1: 远处占比更大
    public ClampedFloatParameter depthPower = new(1.0f, 0.0f, 10.0f);

    /// <summary>
    /// IPostProcessComponent 接口实现
    /// 渲染管线每帧调用此方法决定是否执行对应 Pass
    /// </summary>
    /// <returns>
    /// true = 入队渲染 Pass；false = 跳过（零 GPU 开销）
    /// </returns>
    /// <remarks>
    /// 此处采用"显式开关 + active"双重检查模式
    /// 因为 nearColor/farColor/depthPower 均有合法非零默认值
    /// 无法像 GreyscaleSettings 那样通过参数值隐式判断激活状态
    /// </remarks>
    public bool IsActive()
    {
        return enabled.value && active;
    }
}