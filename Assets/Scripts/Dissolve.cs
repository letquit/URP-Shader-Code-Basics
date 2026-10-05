using UnityEngine;

/// <summary>
/// 按正弦波驱动材质的 _CutoffHeight，用来循环播放溶解。
/// 挂到使用 Basics/Dissolve 或 Basics/DissolveAlt 的物体上。
/// </summary>
public class Dissolve : MonoBehaviour
{
    [SerializeField] private float speed;
    [SerializeField] private float offset;
    [SerializeField] private float height;
    [SerializeField] private float strength;
    [SerializeField] private new Renderer renderer;

    private Material material;

    private void Awake()
    {
        if (renderer == null)
            renderer = GetComponent<Renderer>();
    }

    private void Start()
    {
        if (renderer == null)
        {
            enabled = false;
            return;
        }

        material = renderer.material;
    }

    private void Update()
    {
        if (material == null) return;

        float t = Mathf.Sin(Time.time * speed + offset) * strength;
        material.SetFloat("_CutoffHeight", t + height);
    }
}
