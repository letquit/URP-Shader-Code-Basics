using System;
using UnityEngine;
using UnityEngine.Rendering;

// 【关键】VolumeComponentMenu 属性注册到 Volume Override 下拉菜单
// 路径格式："分类/显示名称"，支持多级目录如 "Basics/Color/Greyscale"
// 缺少此属性时，该类不会出现在 Volume 的 Add Override 列表中
[Serializable, VolumeComponentMenu("Basics/Greyscale")]
public class GreyscaleSettings : VolumeComponent, IPostProcessComponent
{
    // ===== 参数声明 =====
    // ClampedFloatParameter 是 Volume 系统的专用参数类型
    // 相比普通 float，它提供：
    //   1. Inspector 中自动绘制带滑块的 Clamp 控件
    //   2. Volume Blend 时的正确插值行为（Lerp + Clamp）
    //   3. 序列化与 Profile 资产兼容
    // 构造函数参数：(默认值, 最小值, 最大值)
    public ClampedFloatParameter strength = new(0.0f, 0.0f, 1.0f);

    /// <summary>
    /// 【IPostProcessComponent 接口】判断此效果是否应被执行
    /// </summary>
    /// <returns>
    /// true = 渲染管线应执行此 Pass
    /// false = 渲染管线跳过此 Pass（零 GPU 开销）
    /// </returns>
    /// <remarks>
    /// 必须同时检查两个条件：
    /// - active: Volume Component 左侧的勾选框状态
    /// - strength.value > 0: 参数是否有实际效果
    /// 当 strength == 0 时返回 false 可避免无意义的全屏 Blit
    /// </remarks>
    public bool IsActive()
    {
        return strength.value > 0.0f && active;
    }
}