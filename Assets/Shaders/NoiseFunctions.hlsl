// ============================================================================
// GPU 端程序化噪声生成库（Perlin + Voronoi）
// 完全在 Shader 中实时计算，无需采样纹理
// 常用于：动态水面、云层、地形高度图、魔法特效、屏幕空间后处理扰动
// ============================================================================

// ----------------------------------------------------------------------------
// 伪随机向量生成器
// 基于坐标种子生成 2D 单位伪随机向量
// timeOffset 参数允许同一空间位置随时间产生不同的随机结果（用于动画）
// ----------------------------------------------------------------------------
inline float2 randomVector(float2 seed, float timeOffset = 0.0f)
{
    // 经典 GPU 哈希函数：将 2D 坐标投影到 1D，再通过大质数乘法 + sin 打散周期性
    // 12.9898 / 78.233 为经验常数，43758.5453 为大质数，确保 sin 输出在 [-1,1] 间高频震荡
    float a = sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453 + timeOffset;

    // 利用 sin/cos 的正交性，直接输出归一化的 2D 随机方向向量
    // 避免了 normalize() 的开销，且保证长度恒为 1
    return float2(sin(a), cos(a));
}

// ----------------------------------------------------------------------------
// 单八度（Single Octave）Perlin Noise 核心实现
// 返回值范围近似 [0, 1]（经末尾 *0.5+0.5 映射）
// ----------------------------------------------------------------------------
inline float perlinNoiseSingleOctave(float2 uv, float timeOffset = 0.0f)
{
    // 【网格划分】获取当前像素所在的整数网格坐标和小数偏移
    float2 i = floor(uv);      // 网格左下角整数坐标
    float2 f = frac(uv);       // 像素在网格内的局部坐标 [0,1)

    // 【四角定义】确定当前 2×2 网格的四个顶点坐标
    float2 c0 = i;                          // Bottom-Left
    float2 c1 = i + float2(1.0, 0.0);       // Bottom-Right
    float2 c2 = i + float2(0.0, 1.0);       // Top-Left
    float2 c3 = i + float2(1.0, 1.0);       // Top-Right

    // 【梯度点积】Perlin Noise 的核心：每个网格顶点有一个随机梯度向量
    // 将该顶点到当前像素的方向向量与梯度向量做点积，得到该顶点对当前像素的影响值
    // randomVector 使用顶点坐标作为种子，确保相邻网格共享顶点时梯度一致（连续性保证）
    float r0 = dot(randomVector(c0, timeOffset), f);                    // BL: 方向 = f - (0,0) = f
    float r1 = dot(randomVector(c1, timeOffset), f - float2(1.0, 0.0)); // BR: 方向 = f - (1,0)
    float r2 = dot(randomVector(c2, timeOffset), f - float2(0.0, 1.0)); // TL: 方向 = f - (0,1)
    float r3 = dot(randomVector(c3, timeOffset), f - float2(1.0, 1.0)); // TR: 方向 = f - (1,1)

    // 【平滑插值】Hermite 平滑曲线：6t⁵ - 15t⁴ + 10t³ 的简化版 3t² - 2t³
    // 消除线性插值在网格边界处的一阶导数不连续（避免可见的网格痕迹）
    f = f * f * (3.0 - 2.0 * f);

    // 【双线性插值】先在 X 方向插值底边和顶边，再在 Y 方向插值
    float bottomOfGrid = lerp(r0, r1, f.x);
    float topOfGrid = lerp(r2, r3, f.x);

    // 原始 Perlin Noise 输出范围为 [-√2/2, √2/2] ≈ [-0.707, 0.707]
    // *0.5+0.5 将其映射到 [0, 1] 方便后续作为颜色 / 高度使用
    float t = lerp(bottomOfGrid, topOfGrid, f.y) * 0.5f + 0.5f;
    return t;
}

// ----------------------------------------------------------------------------
// 固定 3 八度的 FBM（Fractal Brownian Motion）分形叠加
// scale: 基础频率缩放；timeOffset: 动画偏移
// 手动展开循环，避免 GPU 循环开销（短循环展开比分支跳转更高效）
// ----------------------------------------------------------------------------
float perlinNoise(float2 uv, float scale, float timeOffset = 0.0f)
{
    float t = 0.0;
    float2 scaledUV = uv * scale;

    // 每层频率翻倍（细节更密），振幅减半（贡献递减）→ 符合自然界的自相似规律
    float freq = 4.0f;
    float amp = 0.5f;
    t += perlinNoiseSingleOctave(scaledUV / freq, timeOffset) * amp;

    freq = 2.0f;
    amp = 0.25f;
    t += perlinNoiseSingleOctave(scaledUV / freq, timeOffset) * amp;

    freq = 1.0f;
    amp = 0.125f;
    t += perlinNoiseSingleOctave(scaledUV / freq, timeOffset) * amp;

    return t; // 理论最大值 ≈ 0.5 + 0.25 + 0.125 = 0.875
}

// ----------------------------------------------------------------------------
// 动态八度版本：octaves 由 CPU 传入，支持 LOD 或质量调节
// ⚠️ 若 octaves 逐像素不同会导致分支发散（divergence），性能下降
//    建议所有线程使用相同的 octaves 值，编译器会自动展开循环
// ----------------------------------------------------------------------------
float perlinNoise(float2 uv, float scale, int octaves, float timeOffset = 0.0f)
{
    float t = 0.0;
    if (octaves < 1) return t;

    float2 scaledUV = uv * scale;
    float freq = 4.0f;
    float amp = 0.5f;

    for (int i = 0; i < octaves; ++i)
    {
        t += perlinNoiseSingleOctave(scaledUV / freq, timeOffset) * amp;
        freq *= 0.5f; // 频率倍增 → 细节尺度缩小
        amp *= 0.5f;  // 振幅衰减 → 高频细节权重降低
    }

    return t;
}

// ----------------------------------------------------------------------------
// Voronoi 噪声（含边缘距离）
// 基于 Inigo Quilez 的经典 Voronoi Lines 算法
// https://iquilezles.org/articles/voronoilines/
//
// cellDensity:    细胞密度（越大细胞越小越密）
// distFromCenter: 输出当前像素到最近特征点的距离（可用于细胞着色）
// distFromEdge:   输出当前像素到最近细胞边界的距离（可用于绘制细胞边框 / 裂纹）
// ----------------------------------------------------------------------------
void voronoiNoise(float2 uv, float cellDensity, out float distFromCenter, out float distFromEdge, float timeOffset = 0.0f)
{
    // 将 UV 缩放到细胞空间，获取当前所在细胞的整数坐标和局部坐标
    int2 cell = floor(uv * cellDensity);
    float2 posInCell = frac(uv * cellDensity);

    // 初始化为极大值，作为最小值搜索的起点
    distFromCenter = 8.0f;
    distFromEdge = 8.0f;

    // 【预计算 3×3 邻域偏移】
    // Voronoi 需要检查周围 9 个细胞的特征点，预存避免重复计算 randomVector
    float2 cellOffsets[3][3];
    float2 closestOffset;
    int x, y;

    // [unroll(9)] 强制编译器展开循环，消除运行时循环开销
    // 9 次迭代对 GPU 来说展开后是纯顺序指令，比分支跳转更快
    [unroll(9)]
    for (y = -1; y <= 1; ++y)
    {
        for (x = -1; x <= 1; ++x)
        {
            float2 cellToCheck = float2(x, y);
            // 每个细胞的特征点在 [0,1] 内随机分布（*0.5+0.5 映射到中心区域）
            float2 rand = randomVector(cell + cellToCheck, timeOffset) * 0.5f + 0.5f;
            // 存储从当前像素到该特征点的向量
            cellOffsets[x + 1][y + 1] = float2(cellToCheck) - posInCell + rand;
        }
    }

    // 【Pass 1: 寻找最近特征点】
    [unroll(9)]
    for (y = -1; y <= 1; ++y)
    {
        for (x = -1; x <= 1; ++x)
        {
            float2 cellOffset = cellOffsets[x + 1][y + 1];
            // 使用距离平方比较，避免 sqrt 开销（单调性等价）
            float distToPoint = dot(cellOffset, cellOffset);

            if (distToPoint < distFromCenter)
            {
                distFromCenter = distToPoint;
                closestOffset = cellOffset; // 记录最近点的偏移向量
            }
        }
    }

    // 注意：此处未对 distFromCenter 开根号
    // 调用方可根据需要自行 sqrt，或在着色时用平方距离做艺术化处理以节省 ALU

    // 【Pass 2: 计算到最近边界的距离】
    // 原理：两个相邻特征点的垂直平分线即为细胞边界
    // 当前像素到边界的距离 = 投影到两特征点连线法线上的距离
    [unroll(9)]
    for (y = -1; y <= 1; ++y)
    {
        for (x = -1; x <= 1; ++x)
        {
            float2 cellOffset = cellOffsets[x + 1][y + 1];
            // 几何推导：midpoint · normalize(delta) 给出点到垂直平分线的有符号距离
            // 0.5*(A+B) 是中点，normalize(B-A) 是连线方向的法线
            float distFromCurrentEdge = dot(
                0.5f * (cellOffset + closestOffset),
                normalize(cellOffset - closestOffset)
            );

            distFromEdge = min(distFromEdge, distFromCurrentEdge);
        }
    }
}