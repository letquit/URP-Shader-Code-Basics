using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;

public static class SrpBatcherStatus
{
    [MenuItem("Tools/SRP Batcher/Print Selected Shader Status")]
    private static void PrintSelected()
    {
        var shader = Selection.activeObject as Shader;
        if (shader == null)
        {
            Debug.LogError("先在 Project 窗口选中一个 Shader 资源。");
            return;
        }

        var material = new Material(shader);
        try
        {
            ShaderUtil.CompilePass(material, 0, true);
            Debug.Log($"{shader.name}: pass 0 compiled = {ShaderUtil.IsPassCompiled(material, 0)}");

            const BindingFlags flags = BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public;
            foreach (var method in typeof(ShaderUtil).GetMethods(flags))
            {
                if (method.Name.IndexOf("SRPBatcher", StringComparison.OrdinalIgnoreCase) < 0)
                    continue;

                var args = BuildArgs(method, shader, material);
                if (args == null)
                    continue;

                try
                {
                    var result = method.Invoke(null, args);
                    Debug.Log($"{shader.name}: {method.Name} = {result}");
                }
                catch (Exception e)
                {
                    Debug.LogWarning($"{method.Name} failed: {e.InnerException?.Message ?? e.Message}");
                }
            }
        }
        finally
        {
            UnityEngine.Object.DestroyImmediate(material);
        }
    }

    private static object[] BuildArgs(MethodInfo method, Shader shader, Material material)
    {
        var parameters = method.GetParameters();
        if (parameters.Length == 2 && parameters[1].ParameterType == typeof(int))
        {
            if (parameters[0].ParameterType == typeof(Shader))
                return new object[] { shader, 0 };
            if (parameters[0].ParameterType == typeof(Material))
                return new object[] { material, 0 };
        }

        if (parameters.Length == 3 &&
            parameters[1].ParameterType == typeof(int) &&
            parameters[2].ParameterType == typeof(int))
        {
            if (parameters[0].ParameterType == typeof(Shader))
                return new object[] { shader, 0, 0 };
            if (parameters[0].ParameterType == typeof(Material))
                return new object[] { material, 0, 0 };
        }

        return null;
    }
}
