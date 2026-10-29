using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable, VolumeComponentMenu("Nilo Toon/Character Style")]
public sealed class NiloToonVolume : VolumeComponent, IPostProcessComponent
{
    public BoolParameter enable = new BoolParameter(false);
    public ColorParameter characterTint = new ColorParameter(Color.white, true, false, true);
    public ColorParameter shadowTint = new ColorParameter(Color.white, true, false, true);
    public ClampedFloatParameter rimMultiplier = new ClampedFloatParameter(1f, 0f, 4f);
    public ClampedFloatParameter shadowMultiplier = new ClampedFloatParameter(1f, 0f, 2f);
    public ClampedFloatParameter characterSaturation = new ClampedFloatParameter(1f, 0f, 2f);

    public ClampedFloatParameter postSaturation = new ClampedFloatParameter(1f, 0f, 2f);
    public ClampedFloatParameter postContrast = new ClampedFloatParameter(1f, 0f, 2f);
    public ClampedIntParameter colorSteps = new ClampedIntParameter(0, 0, 32);
    public MinFloatParameter bloomThreshold = new MinFloatParameter(1f, 0f);
    public ClampedFloatParameter characterBloom = new ClampedFloatParameter(0f, 0f, 4f);
    public ClampedFloatParameter backgroundBloom = new ClampedFloatParameter(0f, 0f, 4f);
    public ClampedFloatParameter bloomRadius = new ClampedFloatParameter(2f, 0.5f, 8f);

    public bool IsActive() => active && enable.value;
    public bool IsTileCompatible() => false;
    public bool HasBloom() => IsActive() && (characterBloom.value > 0f || backgroundBloom.value > 0f);
    public bool HasPostProcess() => IsActive() && (HasBloom() || colorSteps.value > 1 ||
        !Mathf.Approximately(postSaturation.value, 1f) || !Mathf.Approximately(postContrast.value, 1f));
}
