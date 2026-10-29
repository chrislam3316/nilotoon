// For more information, visit -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

#ifndef Include_NiloZOffset
#define Include_NiloZOffset

// Push an imaginary vertex farther from the camera in view space (linear view-space units),
// then only overwrite original positionCS.z using imaginary vertex's result positionCS.z value
// Will only affect ZTest ZWrite's depth value of vertex shader

// Useful for:
// -Hide ugly outline on face/eye
// -Make eyebrow render on top of hair
// -Solve ZFighting issue without moving geometry
float4 NiloGetNewClipPosWithZOffset(float4 originalPositionCS, float viewSpaceZOffsetAmount)
{
    if(unity_OrthoParams.w == 0)
    {
        ////////////////////////////////
        //Perspective camera case
        ////////////////////////////////
        float2 ProjM_ZRow_ZW = UNITY_MATRIX_P[2].zw;
        float modifiedPositionVS_Z = -originalPositionCS.w + -viewSpaceZOffsetAmount; // push imaginary vertex
        float modifiedPositionCS_Z = modifiedPositionVS_Z * ProjM_ZRow_ZW[0] + ProjM_ZRow_ZW[1];
        originalPositionCS.z = modifiedPositionCS_Z * originalPositionCS.w / (-modifiedPositionVS_Z); // overwrite positionCS.z
        return originalPositionCS;
    }
    else
    {
        ////////////////////////////////
        //Orthographic camera case
        ////////////////////////////////
        // The projection coefficient handles reversed Z, near-plane range and graphics API conventions.
        originalPositionCS.z -= viewSpaceZOffsetAmount * UNITY_MATRIX_P[2][2] * originalPositionCS.w;
        return originalPositionCS;
    }
}

#endif

