using System;
using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UIElements;

namespace ShaderBasics.Editor
{
    /// <summary>
    /// 自定义 PBR 材质编辑器
    /// 对应 Shader 中的 CustomEditor "ShaderBasics.Editor.PBRShaderGUI"
    /// </summary>
    public class PBRShaderGUI : ShaderGUI
    {
        // ===== 属性描述符结构体 =====
        // 将 MaterialProperty 引用、显示标签、Tooltip、Shader Property ID 打包
        // 避免在 OnGUI 中反复调用 FindProperty / PropertyToID
        private struct PBRShaderProperty
        {
            public MaterialProperty prop;      // 运行时从 properties[] 中查找的引用
            public readonly string name;       // Shader Properties 块中的变量名
            public readonly GUIContent info;   // Inspector 显示的标签 + Tooltip
            public readonly int id;            // Shader.PropertyToID 缓存，避免字符串哈希开销
            
            public PBRShaderProperty(string name, string label, string desc)
            {
                prop = null; // 延迟到 FindProperties 中赋值
                this.name = name;
                info = new GUIContent(label, desc);
                id = Shader.PropertyToID(name);
            }
        }

        // ===== 枚举定义（与 Shader 中的 Float 值一一对应）=====
        // Shader 无法直接使用 enum，用 float 存储，GUI 负责转换
        
        private enum SurfaceType { Opaque = 0, Transparent = 1 }
        private enum RenderFace { Front = 2, Back = 1, Both = 0 }
        
        // 【关键】四种透明混合模式的精确 Blend 因子配置
        private enum BlendFunction { Alpha = 0, Premultiply = 1, Additive = 2, Multiply = 3 }
        
        private enum ZWriteControl { Auto = 0, ForceEnabled = 1, ForceDisabled = 2 }
        private enum QueueControl { Auto = 0, UserOverride = 1 }
        
        // 枚举名称数组，供 Popup 下拉菜单使用
        private string[] surfaceTypeNames = Enum.GetNames(typeof(SurfaceType));
        private string[] renderFaceNames = Enum.GetNames(typeof(RenderFace));
        private string[] blendFunctionNames = Enum.GetNames(typeof(BlendFunction));
        private string[] zWriteControlNames = Enum.GetNames(typeof(ZWriteControl));
        private string[] queueControlNames = Enum.GetNames(typeof(QueueControl));
        private string[] compareFunctionNames = Enum.GetNames(typeof(CompareFunction));
        
        // ===== 所有 Shader 属性的声明 =====
        // 构造时仅初始化元数据，prop 引用在 FindProperties 中绑定
        
        // PBR 基础属性
        private PBRShaderProperty baseColor = new("_BaseColor", "Base Color", "Albedo color of the object.");
        private PBRShaderProperty baseTexture = new("_BaseTexture", "Base Texture", "Albedo texture of the object.");
        private PBRShaderProperty useSpecularSetup = new("_UseSpecularSetup", "Use Specular Setup",
            "Should the shader use Specular workflow (instead of Metallic workflow)?");
        private PBRShaderProperty metallicMap = new("_MetallicMap", "Metallic Map",
            "How metallic the object's surface is (only used in metallic workflow mode).");
        private PBRShaderProperty metallic = new("_Metallic", "Metallic",
            "How metallic the object's surface is (only used in metallic workflow mode).");
        private PBRShaderProperty specularMap = new("_SpecularMap", "Specular Map",
            "The color of specular highlights (only used in specular workflow mode).");
        private PBRShaderProperty specularColor = new("_SpecularColor", "Specular Color",
            "The color of specular highlights (only used in specular workflow mode).");
        private PBRShaderProperty smoothnessMap = new("_SmoothnessMap", "Smoothness Map",
            "How smooth (or rough) the microscopic surface of the object is.");
        private PBRShaderProperty smoothness = new("_Smoothness", "Smoothness",
            "How smooth (or rough) the microscopic surface of the object is.");
        private PBRShaderProperty convertFromRoughness = new("_ConvertFromRoughness", "Convert From Roughness",
            "Should the shader treat the smoothness texture as a roughness texture instead?");
        private PBRShaderProperty normalTexture = new("_NormalTexture", "Normal Texture",
            "A texture encoding normal vector offsets at each point on the surface.");
        private PBRShaderProperty normalStrength = new("_NormalStrength", "Normal Strength",
            "How strongly the normal texture is applied to the existing surface normals.");
        private PBRShaderProperty heightMap = new("_HeightMap", "Height Map",
            "The physical height offset of each part of the surface.");
        private PBRShaderProperty heightMapStrength = new("_HeightMapStrength", "Height Map Strength",
            "How strongly the height map values are applied as UV offsets.");
        private PBRShaderProperty occlusionMap = new("_OcclusionMap", "Occlusion Map",
            "The strength of ambient occlusion at each point on the surface.");
        private PBRShaderProperty occlusionStrength = new("_OcclusionStrength", "Occlusion Strength",
            "How strongly the occlusion map values are applied to the surface.");
        private PBRShaderProperty emissionMap = new("_EmissionMap", "Emission Map",
            "The color of emissive (self-illuminated) light on the surface.");
        private PBRShaderProperty emissionColor = new("_EmissionColor", "Emission Color",
            "The color of emissive (self-illuminated) light on the surface.");

        // 表面类型与渲染状态属性
        private PBRShaderProperty surface = new("_Surface", "Surface Type",
            "Choose whether to use opaque or transparent rendering mode.");
        private PBRShaderProperty cutoff = new("_Cutoff", "Alpha Cutoff",
            "Pixels with alpha below this threshold value get discarded.");
        private PBRShaderProperty srcBlend = new("_SrcBlend", "Source Blend",
            "Blend factor for the existing framebuffer RGB contents.");
        private PBRShaderProperty dstBlend = new("_DstBlend", "Destination Blend",
            "Blend factor for the newly drawn object RGB contents.");
        private PBRShaderProperty srcBlendAlpha = new("_SrcBlendAlpha", "Source Blend Alpha",
            "Blend factor for the existing framebuffer alpha contents.");
        private PBRShaderProperty dstBlendAlpha = new("_DstBlendAlpha", "Destination Blend Alpha",
            "Blend factor for the newly drawn object alpha contents.");
        private PBRShaderProperty zWrite = new("_ZWrite", "ZWrite",
            "Should this material write depth information?");
        private PBRShaderProperty zTest = new("_ZTest", "ZTest",
            "Choose which depth test to apply to this object.");
        private PBRShaderProperty cull = new("_Cull", "Render Face",
            "Which faces should the shader draw?");
        private PBRShaderProperty alphaToMask = new("_AlphaToMask", "Alpha To Mask",
            "Should the shader use alpha-to-mask if MSAA is enabled?");
        
        // 高级选项属性
        private PBRShaderProperty castShadows = new("_CastShadows", "Cast Shadows",
            "Should the object cast shadows from realtime lights?");
        private PBRShaderProperty receiveShadows = new("_ReceiveShadows", "Receive Shadows",
            "Should the object receive shadows from realtime lights?");
        private PBRShaderProperty blend = new("_Blend", "Blend Mode",
            "Choose which blending function to use for transparent objects.");
        private PBRShaderProperty alphaClip = new("_AlphaClip", "Alpha Clipping",
            "Choose whether to use alpha clipping.");
        private PBRShaderProperty zWriteControl = new("_ZWriteControl", "ZWrite Control",
            "Choose whether to handle ZWrite automatically, or force it on/off.");
        private PBRShaderProperty queueOffset = new("_QueueOffset", "Sorting Priority",
            "Determines chronological rendering order. Lower values render first.");
        private PBRShaderProperty queueControl = new("_QueueControl", "Queue Control",
            "Controls whether render queue is auto-set or user-overridden.");
        
        private const string missingEditorText = "No MaterialEditor found (PBRShaderGUI)";
        private const int queueOffsetRange = 50;
        
        // URP 提供的折叠面板管理器，支持持久化展开/收起状态
        private readonly MaterialHeaderScopeList materialScopeList = new();
        private MaterialEditor materialEditor;
        private bool firstTimeOpen = true;
        
        /// <summary>
        /// 从 MaterialProperty[] 中查找并绑定所有属性引用
        /// 每次 OnGUI 调用时执行（Unity 序列化系统要求）
        /// </summary>
        private void FindProperties(MaterialProperty[] props)
        {
            baseColor.prop = FindProperty(baseColor.name, props, true);
            baseTexture.prop = FindProperty(baseTexture.name, props, true);
            useSpecularSetup.prop = FindProperty(useSpecularSetup.name, props, true);
            metallicMap.prop = FindProperty(metallicMap.name, props, true);
            metallic.prop = FindProperty(metallic.name, props, true);
            specularMap.prop = FindProperty(specularMap.name, props, true);
            specularColor.prop = FindProperty(specularColor.name, props, true);
            smoothnessMap.prop = FindProperty(smoothnessMap.name, props, true);
            smoothness.prop = FindProperty(smoothness.name, props, true);
            convertFromRoughness.prop = FindProperty(convertFromRoughness.name, props, true);
            normalTexture.prop = FindProperty(normalTexture.name, props, true);
            normalStrength.prop = FindProperty(normalStrength.name, props, true);
            heightMap.prop = FindProperty(heightMap.name, props, true);
            heightMapStrength.prop = FindProperty(heightMapStrength.name, props, true);
            occlusionMap.prop = FindProperty(occlusionMap.name, props, true);
            occlusionStrength.prop = FindProperty(occlusionStrength.name, props, true);
            emissionMap.prop = FindProperty(emissionMap.name, props, true);
            emissionColor.prop = FindProperty(emissionColor.name, props, true);

            surface.prop = FindProperty(surface.name, props, true);
            cutoff.prop = FindProperty(cutoff.name, props, true);
            srcBlend.prop = FindProperty(srcBlend.name, props, true);
            dstBlend.prop = FindProperty(dstBlend.name, props, true);
            srcBlendAlpha.prop = FindProperty(srcBlendAlpha.name, props, true);
            dstBlendAlpha.prop = FindProperty(dstBlendAlpha.name, props, true);
            zWrite.prop = FindProperty(zWrite.name, props, true);
            zTest.prop = FindProperty(zTest.name, props, true);
            cull.prop = FindProperty(cull.name, props, true);
            alphaToMask.prop = FindProperty(alphaToMask.name, props, true);

            castShadows.prop = FindProperty(castShadows.name, props, true);
            receiveShadows.prop = FindProperty(receiveShadows.name, props, true);
            blend.prop = FindProperty(blend.name, props, true);
            alphaClip.prop = FindProperty(alphaClip.name, props, true);
            zWriteControl.prop = FindProperty(zWriteControl.name, props, true);
            queueOffset.prop = FindProperty(queueOffset.name, props, true);
            queueControl.prop = FindProperty(queueControl.name, props, true);
        }

        /// <summary>
        /// 【核心】根据混合模式和表面类型设置正确的 Blend 因子
        /// 这是 ShaderGUI 最关键的逻辑之一
        /// </summary>
        private void SetBlendMode(BlendFunction blendFunction, SurfaceType surfaceType, Material material)
        {
            // 默认 Opaque 混合：One/Zero（直接覆盖）
            var srcBlendRGB = BlendMode.One;
            var dstBlendRGB = BlendMode.Zero;
            var srcBlendA = BlendMode.One;
            var dstBlendA = BlendMode.Zero;

            if (surfaceType == SurfaceType.Transparent)
            {
                switch (blendFunction)
                {
                    case BlendFunction.Alpha:
                        // 标准 Alpha 混合：src * α + dst * (1-α)
                        srcBlendRGB = BlendMode.SrcAlpha;
                        dstBlendRGB = BlendMode.OneMinusSrcAlpha;
                        srcBlendA = BlendMode.One;
                        dstBlendA = BlendMode.OneMinusSrcAlpha;
                        break;
                    case BlendFunction.Premultiply:
                        // 预乘 Alpha：src + dst * (1-α)，避免边缘黑边
                        srcBlendRGB = BlendMode.One;
                        dstBlendRGB = BlendMode.OneMinusSrcAlpha;
                        srcBlendA = BlendMode.One;
                        dstBlendA = BlendMode.OneMinusSrcAlpha;
                        break;
                    case BlendFunction.Additive:
                        // 叠加混合：src * α + dst，用于光效/粒子
                        srcBlendRGB = BlendMode.SrcAlpha;
                        dstBlendRGB = BlendMode.One;
                        srcBlendA = BlendMode.One;
                        dstBlendA = BlendMode.One;
                        break;
                    case BlendFunction.Multiply:
                        // 正片叠底：dst * src，用于暗色叠加
                        srcBlendRGB = BlendMode.DstColor;
                        dstBlendRGB = BlendMode.Zero;
                        srcBlendA = BlendMode.Zero;
                        dstBlendA = BlendMode.One;
                        break;
                }
            }
            
            // 写入材质的混合模式属性，Shader 中通过 [_SrcBlend] 等语法读取
            material.SetFloat(srcBlend.id, (float)srcBlendRGB);
            material.SetFloat(dstBlend.id, (float)dstBlendRGB);
            material.SetFloat(srcBlendAlpha.id, (float)srcBlendA);
            material.SetFloat(dstBlendAlpha.id, (float)dstBlendA);
        }
        
        /// <summary>
        /// Unity 回调：绘制材质 Inspector UI
        /// </summary>
        public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
        {
            if (materialEditor == null)
                throw new ArgumentNullException(missingEditorText);
            
            this.materialEditor = materialEditor;
            var material = materialEditor.target as Material;

            FindProperties(properties);

            // 首次打开时注册折叠面板（避免重复注册）
            if (firstTimeOpen)
            {
                materialScopeList.RegisterHeaderScope(
                    new GUIContent("Surface Options"), 1u << 0, DrawSurfaceProperties);
                materialScopeList.RegisterHeaderScope(
                    new GUIContent("PBR Inputs"), 1u << 1, DrawPBRProperties);
                materialScopeList.RegisterHeaderScope(
                    new GUIContent("Advanced Options"), 1u << 2, DrawAdvancedSettings);
                firstTimeOpen = false;
            }

            // 绘制所有已注册的折叠面板
            materialScopeList.DrawHeaders(materialEditor, material);
            
            // 【重要】应用所有修改到序列化对象，触发 Undo/Redo 和脏标记
            materialEditor.serializedObject.ApplyModifiedProperties();
        }

        /// <summary>
        /// 绘制 Surface Options 面板
        /// 包含表面类型、混合模式、Alpha 裁剪、深度写入、阴影等核心渲染状态
        /// </summary>
        private void DrawSurfaceProperties(Material material)
        {
            // 表面类型下拉框
            materialEditor.PopupShaderProperty(surface.prop, surface.info, surfaceTypeNames);
            var surfaceTypeValue = (SurfaceType)material.GetFloat(surface.id);

            // 仅透明模式显示混合模式下拉框
            if (surfaceTypeValue == SurfaceType.Transparent)
                materialEditor.PopupShaderProperty(blend.prop, blend.info, blendFunctionNames);

            var blendFuncValue = (BlendFunction)material.GetFloat(blend.id);

            materialEditor.PopupShaderProperty(cull.prop, cull.info, renderFaceNames);
            materialEditor.PopupShaderProperty(zWriteControl.prop, zWriteControl.info, zWriteControlNames);
            materialEditor.PopupShaderProperty(zTest.prop, zTest.info, compareFunctionNames);

            // Alpha Clipping Toggle（手动绘制以支持条件显示 Cutoff 滑块）
            var alphaClipValue = material.GetFloat(alphaClip.id) > 0.5f;
            EditorGUI.BeginChangeCheck();
            alphaClipValue = EditorGUILayout.Toggle(alphaClip.info, alphaClipValue);
            if (EditorGUI.EndChangeCheck())
            {
                Undo.RecordObject(material, "Toggle Alpha Clipping");
                material.SetFloat(alphaClip.id, alphaClipValue ? 1.0f : 0.0f);
            }
            
            if (alphaClipValue)
            {
                EditorGUI.indentLevel++;
                materialEditor.ShaderProperty(cutoff.prop, cutoff.info);
                EditorGUI.indentLevel--;
            }

            // ===== 根据 Surface Type + Alpha Clip 组合设置渲染状态 =====
            bool useAlphaToMask = false;
            int renderQueueValue = material.shader.renderQueue;
            bool useZWrite = false;

            if (surfaceTypeValue == SurfaceType.Opaque)
            {
                SetBlendMode(blendFuncValue, surfaceTypeValue, material);
                useZWrite = true;
                material.DisableKeyword("_SURFACE_TYPE_TRANSPARENT");

                if (alphaClipValue)
                {
                    // Opaque + AlphaTest → AlphaTest 队列 + _ALPHATEST_ON 关键字
                    material.EnableKeyword("_ALPHATEST_ON");
                    renderQueueValue = (int)RenderQueue.AlphaTest;       // 2450
                    material.SetOverrideTag("RenderType", "AlphaTest");
                    useAlphaToMask = true; // MSAA 下用 Alpha-to-Coverage 替代硬裁剪
                }
                else
                {
                    // 纯 Opaque → Geometry 队列
                    material.DisableKeyword("_ALPHATEST_ON");
                    renderQueueValue = (int)RenderQueue.Geometry;        // 2000
                    material.SetOverrideTag("RenderType", "Opaque");
                }
            }
            else // Transparent
            {
                material.SetOverrideTag("RenderType", "Transparent");
                SetBlendMode(blendFuncValue, surfaceTypeValue, material);
                useZWrite = false; // 透明物体默认不写深度
                renderQueueValue = (int)RenderQueue.Transparent;         // 3000
                material.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");

                // 透明模式也可叠加 Alpha Test（用于裁剪+半透明混合）
                if (alphaClipValue) material.EnableKeyword("_ALPHATEST_ON");
                else material.DisableKeyword("_ALPHATEST_ON");
            }
            
            material.SetFloat(alphaToMask.id, useAlphaToMask ? 1.0f : 0.0f);

            // ZWrite 覆盖控制
            var useZWriteControl = (ZWriteControl)material.GetFloat(zWriteControl.id);
            if (useZWriteControl == ZWriteControl.ForceEnabled) useZWrite = true;
            else if (useZWriteControl == ZWriteControl.ForceDisabled) useZWrite = false;
            
            material.SetFloat(zWrite.id, useZWrite ? 1.0f : 0.0f);
            
            // 【关键】当 ZWrite 关闭时禁用 DepthOnly Pass
            // 避免透明物体写入深度缓冲导致排序错误
            material.SetShaderPassEnabled("DepthOnly", useZWrite);

            // 渲染队列：Auto 模式下 = 基准队列 + Offset；UserOverride 模式由用户手动设置
            if (material.GetFloat(queueControl.id) == (float)QueueControl.Auto)
            {
                renderQueueValue += (int)material.GetFloat(queueOffset.id);
                material.renderQueue = renderQueueValue;
            }

            // Cast Shadows Toggle → 控制 ShadowCaster Pass 启用/禁用
            bool castShadowsValue = material.GetFloat(castShadows.id) > 0.5f;
            EditorGUI.BeginChangeCheck();
            castShadowsValue = EditorGUILayout.Toggle(castShadows.info, castShadowsValue);
            if (EditorGUI.EndChangeCheck())
            {
                Undo.RecordObject(material, "Toggle Cast Shadows");
                material.SetFloat(castShadows.id, castShadowsValue ? 1.0f : 0.0f);
                material.SetShaderPassEnabled("ShadowCaster", castShadowsValue);
            }

            // Receive Shadows Toggle → 控制 _RECEIVE_SHADOWS_OFF 关键字
            bool receiveShadowsValue = material.GetFloat(receiveShadows.id) > 0.5f;
            EditorGUI.BeginChangeCheck();
            receiveShadowsValue = EditorGUILayout.Toggle(receiveShadows.info, receiveShadowsValue);
            if (EditorGUI.EndChangeCheck())
            {
                Undo.RecordObject(material, "Toggle Receive Shadows");
                material.SetFloat(receiveShadows.id, receiveShadowsValue ? 1.0f : 0.0f);

                if (receiveShadowsValue) material.DisableKeyword("_RECEIVE_SHADOWS_OFF");
                else material.EnableKeyword("_RECEIVE_SHADOWS_OFF");
            }
        }

        /// <summary>
        /// 绘制 PBR Inputs 面板
        /// 根据工作流切换动态显示 Metallic 或 Specular 属性
        /// </summary>
        private void DrawPBRProperties(Material material)
        {
            // Base Texture + Base Color 单行显示
            materialEditor.TexturePropertySingleLine(baseTexture.info, baseTexture.prop, baseColor.prop);
            materialEditor.TextureScaleOffsetProperty(baseTexture.prop);
            
            materialEditor.ShaderProperty(useSpecularSetup.prop, useSpecularSetup.info);

            // 【关键】根据工作流条件显示不同属性
            if (useSpecularSetup.prop.intValue > 0)
                materialEditor.TexturePropertySingleLine(specularMap.info, specularMap.prop, specularColor.prop);
            else
                materialEditor.TexturePropertySingleLine(metallicMap.info, metallicMap.prop, metallic.prop);
            
            materialEditor.TexturePropertySingleLine(smoothnessMap.info, smoothnessMap.prop, smoothness.prop);
            materialEditor.ShaderProperty(convertFromRoughness.prop, convertFromRoughness.info);
            materialEditor.TexturePropertySingleLine(normalTexture.info, normalTexture.prop, normalStrength.prop);
            materialEditor.TexturePropertySingleLine(heightMap.info, heightMap.prop, heightMapStrength.prop);
            materialEditor.TexturePropertySingleLine(occlusionMap.info, occlusionMap.prop, occlusionStrength.prop);
            materialEditor.TexturePropertySingleLine(emissionMap.info, emissionMap.prop, emissionColor.prop);
        }

        /// <summary>
        /// 绘制 Advanced Options 面板
        /// 渲染队列控制（Auto Offset / Manual Override）
        /// </summary>
        private void DrawAdvancedSettings(Material material)
        {
            materialEditor.PopupShaderProperty(queueControl.prop, queueControl.info, queueControlNames);

            if (material.GetFloat(queueControl.id) == (float)QueueControl.UserOverride)
            {
                // 用户手动输入渲染队列值
                materialEditor.RenderQueueField();
            }
            else
            {
                // Auto 模式下提供 ±50 的偏移滑块
                materialEditor.IntSliderShaderProperty(
                    queueOffset.prop, -queueOffsetRange, queueOffsetRange, queueOffset.info);
            }
        }
    }
}