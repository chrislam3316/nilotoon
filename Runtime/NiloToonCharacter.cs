using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Shares character data across mesh parts without selecting a camera.
/// This component owns each selected material index's property block while enabled.
/// Disabling/refreshing restores the exact original block; other writers must use a
/// different material index. Existing renderer-wide overrides are copied on enable.
/// </summary>
[ExecuteAlways, DisallowMultipleComponent]
public sealed class NiloToonCharacter : MonoBehaviour
{
    [Tooltip("Empty means gather child Renderers. Refresh Targets after changing materials or the hierarchy.")]
    public Renderer[] targetRenderers;
    [Tooltip("Shared projection anchor for body, hair, face and clothing. Defaults to this transform.")]
    public Transform pivot;
    [Tooltip("Head +Z is forward and +X is right. Defaults to this transform.")]
    public Transform head;
    [Range(0, 1)] public float perspectiveCorrection;
    public Color characterTint = Color.white;
    [Range(0, 1)] public float fade = 1;
    [Range(0, 1)] public float dissolve;
    [Min(0)] public float rimMultiplier = 1;
    [Min(0)] public float outlineMultiplier = 1;
    [Min(0), Tooltip("Extra local bounds in each direction. Increase for wide FOV/close views and large outlines; not an automatic bound on arbitrary projection changes.")]
    public float boundsPadding = 0.5f;

    static readonly int Perspective = Shader.PropertyToID("_PerspectiveCorrection");
    static readonly int Pivot = Shader.PropertyToID("_CharacterPivotWS");
    static readonly int Id = Shader.PropertyToID("_CharacterId");
    static readonly int Forward = Shader.PropertyToID("_FaceForwardWS");
    static readonly int Right = Shader.PropertyToID("_FaceRightWS");
    static readonly int Tint = Shader.PropertyToID("_CharacterTint");
    static readonly int Fade = Shader.PropertyToID("_CharacterFade");
    static readonly int Dissolve = Shader.PropertyToID("_DissolveAmount");
    static readonly int Rim = Shader.PropertyToID("_CharacterRimMultiplier");
    static readonly int Outline = Shader.PropertyToID("_CharacterOutlineMultiplier");
    static readonly HashSet<int> ActiveIds = new HashSet<int>();
    static int nextId = 1;

    sealed class Slot
    {
        public int index;
        public Material material;
        public MaterialPropertyBlock original;
        public MaterialPropertyBlock current = new MaterialPropertyBlock();
    }

    sealed class Target
    {
        public Renderer renderer;
        public Bounds originalBounds;
        public readonly List<Slot> slots = new List<Slot>();
    }

    readonly List<Target> targets = new List<Target>();
    int characterId;
    bool refreshRequested;

    void OnEnable()
    {
        // IDs remain exact in the float render target, including after repeated enables.
        while (ActiveIds.Contains(nextId))
            nextId = nextId % 16777215 + 1;
        characterId = nextId;
        ActiveIds.Add(characterId);
        nextId = nextId % 16777215 + 1;
        RefreshTargets();
    }

    void OnDisable()
    {
        RestoreTargets();
        ActiveIds.Remove(characterId);
        characterId = 0;
    }

    void OnValidate()
    {
        perspectiveCorrection = Mathf.Clamp01(perspectiveCorrection);
        fade = Mathf.Clamp01(fade);
        dissolve = Mathf.Clamp01(dissolve);
        rimMultiplier = Mathf.Max(0, rimMultiplier);
        outlineMultiplier = Mathf.Max(0, outlineMultiplier);
        boundsPadding = Mathf.Max(0, boundsPadding);
        refreshRequested = true;
    }

    [ContextMenu("Refresh Targets")]
    public void RefreshTargets()
    {
        RestoreTargets();
        refreshRequested = false;
        if (!isActiveAndEnabled)
            return;

        bool gatherChildren = targetRenderers == null || targetRenderers.Length == 0;
        Renderer[] renderers = gatherChildren ? GetComponentsInChildren<Renderer>(true) : targetRenderers;
        var seen = new HashSet<Renderer>();
        foreach (Renderer renderer in renderers)
        {
            if (!renderer || !seen.Add(renderer))
                continue;
            if (gatherChildren && renderer.GetComponentInParent<NiloToonCharacter>() != this)
                continue;

            var target = new Target { renderer = renderer, originalBounds = renderer.localBounds };
            Material[] materials = renderer.sharedMaterials;
            for (int index = 0; index < materials.Length; ++index)
            {
                if (!materials[index] || !materials[index].HasProperty(Perspective))
                    continue;
                var original = new MaterialPropertyBlock();
                renderer.GetPropertyBlock(original, index);
                var slot = new Slot { index = index, material = materials[index], original = original };
                renderer.GetPropertyBlock(slot.current, index);
                if (slot.current.isEmpty)
                    renderer.GetPropertyBlock(slot.current);
                target.slots.Add(slot);
            }
            if (target.slots.Count == 0)
                continue;
            Bounds padded = target.originalBounds;
            padded.Expand(boundsPadding * 2);
            renderer.localBounds = padded;
            targets.Add(target);
        }
        ApplyProperties();
    }

    void LateUpdate()
    {
        if (refreshRequested)
            RefreshTargets();
        else
            ApplyProperties();
    }

    void ApplyProperties()
    {
        Vector3 position = (pivot ? pivot : transform).position;
        Transform orientation = head ? head : transform;
        foreach (Target target in targets)
        {
            if (!target.renderer)
                continue;
            foreach (Slot slot in target.slots)
            {
                if (!slot.material)
                    continue;
                // Merge unrelated values during use; restore the original snapshot on disable.
                target.renderer.GetPropertyBlock(slot.current, slot.index);
                if (slot.current.isEmpty)
                    target.renderer.GetPropertyBlock(slot.current);
                SetFloat(slot, Perspective, Mathf.Clamp01(perspectiveCorrection));
                SetVector(slot, Pivot, new Vector4(position.x, position.y, position.z, 1));
                SetFloat(slot, Id, characterId);
                SetVector(slot, Forward, orientation.forward);
                SetVector(slot, Right, orientation.right);
                if (slot.material.HasProperty(Tint))
                    slot.current.SetColor(Tint, characterTint);
                SetFloat(slot, Fade, Mathf.Clamp01(fade));
                SetFloat(slot, Dissolve, Mathf.Clamp01(dissolve));
                SetFloat(slot, Rim, Mathf.Max(0, rimMultiplier));
                SetFloat(slot, Outline, Mathf.Max(0, outlineMultiplier));
                target.renderer.SetPropertyBlock(slot.current, slot.index);
            }
        }
    }

    static void SetFloat(Slot slot, int property, float value)
    {
        if (slot.material.HasProperty(property))
            slot.current.SetFloat(property, value);
    }

    static void SetVector(Slot slot, int property, Vector4 value)
    {
        if (slot.material.HasProperty(property))
            slot.current.SetVector(property, value);
    }

    void RestoreTargets()
    {
        foreach (Target target in targets)
        {
            if (!target.renderer)
                continue;
            int materialCount = target.renderer.sharedMaterials.Length;
            foreach (Slot slot in target.slots)
                if (slot.index < materialCount)
                    target.renderer.SetPropertyBlock(slot.original.isEmpty ? null : slot.original, slot.index);
            target.renderer.localBounds = target.originalBounds;
        }
        targets.Clear();
    }
}
