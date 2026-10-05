using System;
using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UIElements;

namespace ShaderBasics.Editor
{
    /// <summary>
    /// 自定义溶解 Shader 的材质编辑器 GUI
    /// 继承 PBRShaderGUI 以复用 URP 标准 PBR 属性的绘制逻辑（Surface Options、PBR Inputs 等）
    /// 仅额外添加 "Dissolve Properties" 折叠面板
    /// </summary>
    public class DissolveShaderGUI : PBRShaderGUI
    {
        // ===== 噪声类型枚举 =====
        // 仅 DissolveAlt Shader 使用；主 Dissolve Shader 不包含 _NoiseType 属性
        // 通过 Shader Keyword 切换，避免运行时分支开销
        private enum NoiseType
        {
            Perlin = 0,         // 柏林噪声：连续平滑的云雾状溶解
            VoronoiCenter = 1,  // Voronoi 细胞中心距离：从细胞中心向外溶解
            VoronoiEdge = 2     // Voronoi 边缘距离：沿细胞边界/裂纹溶解
        }

        // ===== 溶解相关属性封装 =====
        // PBRShaderProperty 是 URP ShaderGUI 的属性包装器，统一管理属性查找与显示
        private PBRShaderProperty noiseScale = new("_NoiseScale", "Noise Scale", "");
        private PBRShaderProperty noiseStrength = new("_NoiseStrength", "Noise Strength", "");
        private PBRShaderProperty cutoffHeight = new("_CutoffHeight", "Cutoff Height", "");
        private PBRShaderProperty edgeColor = new("_EdgeColor", "Edge Color", "");
        private PBRShaderProperty edgeThickness = new("_EdgeThickness", "Edge Thickness", "");
        private PBRShaderProperty cycleSpeed = new("_CycleSpeed", "Cycle Speed", "");

        // 以下三个属性仅存在于 DissolveAlt Shader 中
        // FindProperty(..., false) 在主 Dissolve 上会返回 null，绘制时需做空值检查
        private PBRShaderProperty noiseType = new("_NoiseType", "Noise Type", "");
        private PBRShaderProperty reverseDirection = new("_ReverseDirection", "Reverse Direction", "");
        private PBRShaderProperty useHeightCutoff = new("_UseHeightCutoff", "Add Noise To Height", "");

        /// <summary>
        /// 查找并绑定所有材质属性
        /// base.FindProperties 负责查找 PBR 标准属性（BaseColor、Metallic、Smoothness 等）
        /// </summary>
        protected override void FindProperties(MaterialProperty[] props)
        {
            base.FindProperties(props);

            // 溶解通用属性：两个 Shader 都有，强制查找（true = 找不到则报错）
            noiseScale.prop = FindProperty(noiseScale.name, props, true);
            noiseStrength.prop = FindProperty(noiseStrength.name, props, true);
            cutoffHeight.prop = FindProperty(cutoffHeight.name, props, true);
            edgeColor.prop = FindProperty(edgeColor.name, props, true);
            edgeThickness.prop = FindProperty(edgeThickness.name, props, true);
            cycleSpeed.prop = FindProperty(cycleSpeed.name, props, true);

            // DissolveAlt 专属属性：可选查找（false = 找不到返回 null，不报错）
            // 这使得同一个 GUI 类可以同时服务于两个不同的 Shader
            noiseType.prop = FindProperty(noiseType.name, props, false);
            reverseDirection.prop = FindProperty(reverseDirection.name, props, false);
            useHeightCutoff.prop = FindProperty(useHeightCutoff.name, props, false);
        }

        /// <summary>
        /// 绘制材质 Inspector 面板入口
        /// 使用 MaterialHeaderScopeList 实现可折叠的面板分组
        /// </summary>
        public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
        {
            if (materialEditor == null)
            {
                throw new ArgumentNullException(missingEditorText);
            }

            this.materialEditor = materialEditor;
            var material = materialEditor.target as Material;

            FindProperties(properties);

            // 首次打开时注册四个折叠面板
            // 位掩码 (1u << N) 用于持久化面板的展开/折叠状态到 EditorPrefs
            if (firstTimeOpen)
            {
                materialScopeList.RegisterHeaderScope(
                    new GUIContent("Surface Options"), 1u << 0, DrawSurfaceProperties);
                materialScopeList.RegisterHeaderScope(
                    new GUIContent("PBR Inputs"), 1u << 1, DrawPBRProperties);
                // ⭐ 自定义面板：溶解专属参数
                materialScopeList.RegisterHeaderScope(
                    new GUIContent("Dissolve Properties"), 1u << 2, DrawDissolveProperties);
                materialScopeList.RegisterHeaderScope(
                    new GUIContent("Advanced Options"), 1u << 3, DrawAdvancedSettings);
                firstTimeOpen = false;
            }

            // 绘制所有已注册的面板
            materialScopeList.DrawHeaders(materialEditor, material);
            // 应用所有未提交的修改（支持 Undo/Redo 和多材质批量编辑）
            materialEditor.serializedObject.ApplyModifiedProperties();
        }

        /// <summary>
        /// 绘制溶解属性面板内容
        /// 兼容主 Dissolve（无 noiseType）和 DissolveAlt（有 noiseType）两种 Shader
        /// </summary>
        private void DrawDissolveProperties(Material material)
        {
            // 通用属性：两个 Shader 都绘制
            materialEditor.ShaderProperty(noiseScale.prop, noiseScale.info);
            materialEditor.ShaderProperty(noiseStrength.prop, noiseStrength.info);

            // DissolveAlt 专属：仅在属性存在时绘制
            if (useHeightCutoff.prop != null)
                materialEditor.ShaderProperty(useHeightCutoff.prop, useHeightCutoff.info);

            materialEditor.ShaderProperty(cutoffHeight.prop, cutoffHeight.info);
            materialEditor.ShaderProperty(edgeColor.prop, edgeColor.info);
            materialEditor.ShaderProperty(edgeThickness.prop, edgeThickness.info);
            materialEditor.ShaderProperty(cycleSpeed.prop, cycleSpeed.info);

            // ===== NoiseType 下拉框（仅 DissolveAlt）=====
            if (noiseType.prop != null)
            {
                var noiseTypeValue = (NoiseType)material.GetFloat(noiseType.id);

                // BeginChangeCheck / EndChangeCheck 包裹手动绘制的控件
                // 用于检测用户是否修改了值，以便触发关键字更新和 Undo 记录
                EditorGUI.BeginChangeCheck();
                noiseTypeValue = (NoiseType)EditorGUILayout.EnumPopup(noiseType.info, noiseTypeValue);
                if (EditorGUI.EndChangeCheck())
                {
                    // ⚠️ 多材质批量编辑支持：必须遍历所有选中材质
                    // materialEditor.targets 包含当前 Inspector 中选中的所有材质对象
                    foreach (var target in materialEditor.targets)
                    {
                        var targetMaterial = target as Material;
                        if (targetMaterial == null) continue;

                        // 记录 Undo 操作，使修改可撤销
                        Undo.RecordObject(targetMaterial, "Change Noise Type");
                        targetMaterial.SetFloat(noiseType.id, (float)noiseTypeValue);
                        // 同步更新 Shader Keyword，确保渲染结果与 UI 选择一致
                        SetNoiseTypeKeywords(targetMaterial, noiseTypeValue);
                    }
                }

                // Reverse Direction 也是 DissolveAlt 专属
                if (reverseDirection.prop != null)
                    materialEditor.ShaderProperty(reverseDirection.prop, reverseDirection.info);
            }
        }

        /// <summary>
        /// 材质验证回调：在材质导入、重置、或 Shader 变更时自动调用
        /// 确保 Shader Keyword 状态始终与 _NoiseType 浮点值同步
        /// 防止手动修改材质序列化数据或版本升级导致的关键字不一致
        /// </summary>
        public override void ValidateMaterial(Material material)
        {
            base.ValidateMaterial(material);

            // 主 Dissolve Shader 没有 _NoiseType 属性，直接跳过
            if (material == null || !material.HasProperty("_NoiseType"))
                return;

            SetNoiseTypeKeywords(material, (NoiseType)material.GetFloat(noiseType.id));
        }

        /// <summary>
        /// 根据 NoiseType 枚举值设置对应的 Shader Keyword
        /// 使用互斥关键字组：同一时刻只有一个噪声类型关键字处于启用状态
        /// Shader 中通过 #pragma shader_feature_local 声明这些关键字
        /// </summary>
        private static void SetNoiseTypeKeywords(Material material, NoiseType noiseTypeValue)
        {
            if (noiseTypeValue == NoiseType.Perlin)
            {
                material.EnableKeyword("_NOISE_TYPE_PERLIN");
                material.DisableKeyword("_NOISE_TYPE_VRN_CENTER");
                material.DisableKeyword("_NOISE_TYPE_VRN_EDGE");
            }
            else if (noiseTypeValue == NoiseType.VoronoiCenter)
            {
                material.DisableKeyword("_NOISE_TYPE_PERLIN");
                material.EnableKeyword("_NOISE_TYPE_VRN_CENTER");
                material.DisableKeyword("_NOISE_TYPE_VRN_EDGE");
            }
            else // VoronoiEdge
            {
                material.DisableKeyword("_NOISE_TYPE_PERLIN");
                material.DisableKeyword("_NOISE_TYPE_VRN_CENTER");
                material.EnableKeyword("_NOISE_TYPE_VRN_EDGE");
            }
        }
    }
}