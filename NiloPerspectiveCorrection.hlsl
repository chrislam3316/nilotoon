#pragma once

// Use the camera currently drawing this pass, including its lens shift and stereo eye.
float4 NiloCorrectPerspective(float3 positionWS, float4 originalCS)
{
    if (_PerspectiveCorrection <= 0 || unity_OrthoParams.w > 0.5 || originalCS.w <= 0.00001)
        return originalCS;

    float3 positionVS = TransformWorldToView(positionWS);
    float3 pivotWS = _CharacterPivotWS.w > 0.5
        ? _CharacterPivotWS.xyz : TransformObjectToWorld(float3(0, 0, 0));
    float3 pivotVS = TransformWorldToView(pivotWS);
    float nearPlane = max(_ProjectionParams.y, 0.00001);
    if (-positionVS.z <= nearPlane || -pivotVS.z <= nearPlane)
        return originalCS;

    float amount = saturate(_PerspectiveCorrection) * smoothstep(nearPlane, 2 * nearPlane, -pivotVS.z);
    float virtualZ = lerp(positionVS.z, pivotVS.z, amount);
    float4 correctedCS = mul(UNITY_MATRIX_P, float4(positionVS.xy, virtualZ, 1));
    if (correctedCS.w <= 0.00001)
        return originalCS;

    // Preserve vertex depth; use virtual w so textures become affine at full correction.
    correctedCS.z = (originalCS.z / originalCS.w) * correctedCS.w;
    // shortcut: screen-space position reconstruction is approximate after warping; use modest correction near scenery.
    return correctedCS;
}
