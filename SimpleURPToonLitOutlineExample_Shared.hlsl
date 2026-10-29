// Shared geometry and clipping keep all camera passes aligned. Shadows use the original mesh.
#pragma once
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
#include "NiloZOffset.hlsl"

TEXTURE2D(_BaseMap);
TEXTURE2D(_BumpMap);
TEXTURE2D(_DetailMap);
TEXTURE2D(_HeightMap);
TEXTURE2D(_EmissionMap);
TEXTURE2D(_OcclusionMap);
TEXTURE2D(_ShadowTintMap);
TEXTURE2D(_FaceShadowMap);
TEXTURE2D(_MaterialMask);
TEXTURE2D(_MatCapMap);
TEXTURE2D(_OutlineMask);
TEXTURE2D(_OutlineZOffsetMaskTex);
TEXTURE2D(_DissolveMap);
TEXTURE2D(_BloomMask);
SAMPLER(sampler_BaseMap);
TEXTURE2D_X_FLOAT(_NiloHairDepthTexture);
float _NiloHairDepthAvailable;
float _NiloGlobalStyleEnabled;
float4 _NiloGlobalStyle, _NiloGlobalTint, _NiloGlobalShadowTint;

CBUFFER_START(UnityPerMaterial)
    float _IsFace;
    float _IsHair;
    float _IsEye;
    float _Cull;
    float _PerspectiveCorrection;
    float4 _CharacterPivotWS;
    float _CharacterId;
    float4 _CharacterTint;
    float _CharacterFade;
    float _CharacterRimMultiplier;
    float _CharacterOutlineMultiplier;
    float4 _BaseColor;
    float _Cutoff;
    float _BumpScale;
    float _DetailStrength;
    float _Parallax;
    float _UseEmission;
    float4 _EmissionColor;
    float _EmissionMulByBaseColor;
    float4 _EmissionMapChannelMask;
    float _UseOcclusion;
    float _OcclusionStrength;
    float4 _OcclusionMapChannelMask;
    float _OcclusionRemapStart;
    float _OcclusionRemapEnd;
    float4 _IndirectLightMinColor;
    float _IndirectLightMultiplier;
    float _DirectLightMultiplier;
    float _CelShadeMidPoint;
    float _CelShadeSoftness;
    float _MainLightIgnoreCelShade;
    float _AdditionalLightIgnoreCelShade;
    float _ReceiveShadowMappingAmount;
    float4 _ShadowMapColor;
    float _ReceiveShadowMappingPosOffset;
    float _UseFaceSDF;
    float _FaceShadowSoftness;
    float4 _FaceForwardWS;
    float4 _FaceRightWS;
    float _HairShadowStrength;
    float _HairShadowOffsetPixels;
    float _HairShadowMaxDistance;
    float _EyeOverlayOpacity;
    float _EyeOverlayMaxDistance;
    float _SpecularStrength;
    float _Metallic;
    float _Roughness;
    float4 _MatCapColor;
    float _MatCapStrength;
    float _MatCapMode;
    float4 _SSSColor;
    float _SSSStrength;
    float4 _RimColor;
    float _RimStrength;
    float _RimWidthPixels;
    float _RimDepthThreshold;
    float _OutlineWidth;
    float4 _OutlineColor;
    float _UseSmoothOutlineNormal;
    float _OutlineZOffset;
    float _OutlineZOffsetMaskRemapStart;
    float _OutlineZOffsetMaskRemapEnd;
    float _ExtraOutlineWidth;
    float4 _ExtraOutlineColor;
    float4 _ColorHSV;
    float4 _OutlineHSV;
    float _DissolveAmount;
    float _DissolveEdgeWidth;
    float4 _DissolveEdgeColor;
    float _BloomMaskStrength;
    float4 _BaseMap_ST, _DetailMap_ST;
CBUFFER_END

#include "NiloPerspectiveCorrection.hlsl"

float3 _LightDirection, _LightPosition;
struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    float3 smoothNormalTS : TEXCOORD3;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};
struct Varyings
{
    float4 positionCS : SV_POSITION;
    float3 positionWS : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float4 tangentWS : TEXCOORD2;
    float2 uv : TEXCOORD3;
    float2 rawUV : TEXCOORD4;
    half fogFactor : TEXCOORD5;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};
struct ToonSurfaceData
{
    half3 albedo, emission, shadowTint;
    half alpha, occlusion, metallic, roughness, specularMask, faceShadow, faceShadowMirrored;
};
struct ToonLightingData
{
    half3 normalWS, viewDirectionWS;
    float3 positionWS;
    float4 shadowCoord;
    float2 screenUV;
    float eyeDepth;
};

float RemapMask(float start, float end, float value)
{
    float range = end - start;
    return abs(range) < 0.00001 ? step(end, value) : saturate((value - start) / range);
}
float2 PixelDirection(float2 ndcDirection)
{
    float2 direction = ndcDirection * _ScaledScreenParams.xy;
    return direction * rsqrt(max(dot(direction, direction), 0.00000001));
}
Varyings VertexShaderWork(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
    VertexPositionInputs position = GetVertexPositionInputs(input.positionOS);
    VertexNormalInputs normal = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    output.positionWS = position.positionWS;
    output.normalWS = normal.normalWS;
    output.tangentWS = float4(normal.tangentWS, input.tangentOS.w * GetOddNegativeScale());
    output.rawUV = input.uv;
    output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
    output.fogFactor = ComputeFogFactor(position.positionCS.z);
    output.positionCS = position.positionCS;

#ifdef ToonShaderApplyShadowBiasFix
    float3 lightDirection = _LightDirection;
    #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
        lightDirection = SafeNormalize(_LightPosition - position.positionWS);
    #endif
    output.positionCS = TransformWorldToHClip(ApplyShadowBias(position.positionWS, normal.normalWS, lightDirection));
    #if UNITY_REVERSED_Z
        output.positionCS.z = min(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
    #else
        output.positionCS.z = max(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
    #endif
#else
    output.positionCS = NiloCorrectPerspective(position.positionWS, position.positionCS);
    #ifdef ToonShaderIsOutline
        float3 outlineNormal = normal.normalWS;
        if (_UseSmoothOutlineNormal > 0.5 && dot(input.smoothNormalTS, input.smoothNormalTS) > 0.1)
        {
            // UV4 stores a tangent-space direction, so skinned normals/tangents animate the outline too.
            float3 tangent = SafeNormalize(normal.tangentWS - normal.normalWS * dot(normal.tangentWS, normal.normalWS));
            float3 bitangent = cross(normal.normalWS, tangent) * output.tangentWS.w;
            outlineNormal = SafeNormalize(tangent * input.smoothNormalTS.x +
                bitangent * input.smoothNormalTS.y + normal.normalWS * input.smoothNormalTS.z);
        }
        float3 tipWS = position.positionWS + outlineNormal * 0.01;
        float4 tipCS = NiloCorrectPerspective(tipWS, TransformWorldToHClip(tipWS));
        float2 direction = PixelDirection(tipCS.xy / max(tipCS.w, 0.00001)
            - output.positionCS.xy / max(output.positionCS.w, 0.00001));
        float width = _OutlineWidth;
        #ifdef ToonShaderIsExtraOutline
            width += _ExtraOutlineWidth;
        #endif
        width *= max(0, _CharacterOutlineMultiplier) *
            SAMPLE_TEXTURE2D_LOD(_OutlineMask, sampler_BaseMap, input.uv, 0).r;
        output.positionCS.xy += direction * (2 * width / _ScaledScreenParams.xy) * output.positionCS.w;

        float mask = 1 - SAMPLE_TEXTURE2D_LOD(_OutlineZOffsetMaskTex, sampler_BaseMap, input.uv, 0).r;
        mask = RemapMask(_OutlineZOffsetMaskRemapStart, _OutlineZOffsetMaskRemapEnd, mask);
        // Calculate depth offset before replacing w, then transfer only the resulting NDC depth.
        float4 offsetCS = NiloGetNewClipPosWithZOffset(position.positionCS, _OutlineZOffset * mask + 0.03 * _IsFace);
        if (abs(position.positionCS.w) > 0.00001)
            output.positionCS.z = offsetCS.z / position.positionCS.w * output.positionCS.w;
    #endif
#endif
    return output;
}

float3x3 SurfaceTBN(Varyings input)
{
    float3 n = SafeNormalize(input.normalWS);
    float3 t = SafeNormalize(input.tangentWS.xyz - n * dot(input.tangentWS.xyz, n));
    return float3x3(t, cross(n, t) * input.tangentWS.w, n);
}
float2 SurfaceUV(Varyings input)
{
    float2 uv = input.uv;
    if (_Parallax > 0 && dot(input.tangentWS.xyz, input.tangentWS.xyz) > 0.01)
    {
        float3 viewTS = mul(SurfaceTBN(input), GetWorldSpaceNormalizeViewDir(input.positionWS));
        half height = SAMPLE_TEXTURE2D(_HeightMap, sampler_BaseMap, uv).r - 0.5;
        // shortcut: single-step UV parallax has no silhouette/self-shadowing; use POM for deep relief.
        uv += height * _Parallax * viewTS.xy / max(abs(viewTS.z), 0.2);
    }
    return uv;
}
float DitherThreshold(float2 pixel)
{
    return frac(52.9829189 * frac(dot(floor(pixel), float2(0.06711056, 0.00583715))));
}
void ClipMaterial(Varyings input, float2 uv)
{
#if defined(_UseAlphaClipping)
    clip(SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).a * _BaseColor.a - _Cutoff);
#endif
    clip(saturate(_CharacterFade) - DitherThreshold(input.positionCS.xy) - 0.00001);
    if (_DissolveAmount > 0)
        clip(SAMPLE_TEXTURE2D(_DissolveMap, sampler_BaseMap, input.rawUV).r - _DissolveAmount - 0.00001);
}
half3 SurfaceNormal(Varyings input, float2 uv)
{
    half3 n = SafeNormalize(input.normalWS);
    if (_BumpScale > 0 && dot(input.tangentWS.xyz, input.tangentWS.xyz) > 0.01)
    {
        half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BaseMap, uv), _BumpScale);
        n = SafeNormalize(mul(normalTS, SurfaceTBN(input)));
    }
    return n;
}
float EyeDepth(float rawDepth)
{
    if (unity_OrthoParams.w > 0.5)
    {
#if UNITY_REVERSED_Z
        rawDepth = 1 - rawDepth;
#endif
        return lerp(_ProjectionParams.y, _ProjectionParams.z, rawDepth);
    }
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}
ToonSurfaceData InitializeSurfaceData(Varyings input, float2 uv)
{
    ToonSurfaceData surface = (ToonSurfaceData)0;
    half4 base = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
    surface.albedo = base.rgb;
    surface.alpha = base.a;
    if (_DetailStrength > 0)
    {
        half3 detail = SAMPLE_TEXTURE2D(_DetailMap, sampler_BaseMap, TRANSFORM_TEX(input.rawUV, _DetailMap)).rgb;
        surface.albedo *= lerp(1, detail * 2, _DetailStrength);
    }
    surface.occlusion = 1;
    if (_UseOcclusion > 0.5)
    {
        half value = dot(SAMPLE_TEXTURE2D(_OcclusionMap, sampler_BaseMap, uv), _OcclusionMapChannelMask);
        surface.occlusion = RemapMask(_OcclusionRemapStart, _OcclusionRemapEnd, lerp(1, value, _OcclusionStrength));
    }
    if (_UseEmission > 0.5)
        surface.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, uv).rgb * _EmissionMapChannelMask.rgb * _EmissionColor.rgb;
    if (_DissolveAmount > 0)
    {
        half noise = SAMPLE_TEXTURE2D(_DissolveMap, sampler_BaseMap, input.rawUV).r;
        surface.emission += _DissolveEdgeColor.rgb * (1 - smoothstep(_DissolveAmount, _DissolveAmount + max(_DissolveEdgeWidth, 0.0001), noise));
    }
    half3 mask = SAMPLE_TEXTURE2D(_MaterialMask, sampler_BaseMap, uv).rgb;
    surface.metallic = mask.r * _Metallic;
    surface.roughness = max(0.02, mask.g * _Roughness);
    surface.specularMask = mask.b;
    surface.shadowTint = SAMPLE_TEXTURE2D(_ShadowTintMap, sampler_BaseMap, uv).rgb;
    surface.faceShadow = 0.5;
    surface.faceShadowMirrored = 0.5;
    if (_IsFace > 0.5 && _UseFaceSDF > 0.5)
    {
        surface.faceShadow = SAMPLE_TEXTURE2D(_FaceShadowMap, sampler_LinearClamp, input.rawUV).r;
        surface.faceShadowMirrored = SAMPLE_TEXTURE2D(_FaceShadowMap, sampler_LinearClamp, float2(1 - input.rawUV.x, input.rawUV.y)).r;
    }
    return surface;
}
ToonLightingData InitializeLightingData(Varyings input, float2 uv)
{
    ToonLightingData data = (ToonLightingData)0;
    data.positionWS = input.positionWS;
    data.normalWS = SurfaceNormal(input, uv);
    data.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    data.screenUV = GetNormalizedScreenSpaceUV(input.positionCS);
    data.eyeDepth = EyeDepth(input.positionCS.z);
    return data;
}
float2 ReadHair(float2 uv)
{
    return SAMPLE_TEXTURE2D_X(_NiloHairDepthTexture, sampler_PointClamp, UnityStereoTransformScreenSpaceTex(uv)).rg;
}
bool OwnHair(float2 hair)
{
    return _CharacterId > 0 && hair.x > 0 && abs(hair.y - _CharacterId) < 0.5;
}
half HairShadow(ToonLightingData data, float3 lightDirection)
{
    if (_IsFace < 0.5 || _HairShadowStrength <= 0 || _NiloHairDepthAvailable < 0.5)
        return 1;
    float2 lightVS = TransformWorldToViewDir(lightDirection, false).xy;
    lightVS.y *= _ProjectionParams.x;
    float2 uv = data.screenUV + lightVS * _HairShadowOffsetPixels / _ScaledScreenParams.xy;
    if (any(uv < 0) || any(uv > 1))
        return 1;
    float2 hair = ReadHair(uv);
    float gap = data.eyeDepth - hair.x;
    return OwnHair(hair) && gap > 0.001 && gap < _HairShadowMaxDistance ? 1 - _HairShadowStrength : 1;
}

#include "SimpleURPToonLitOutlineExample_LightingEquation.hlsl"

half3 ShadeAllLights(ToonSurfaceData surface, ToonLightingData data)
{
    Light mainLight = GetMainLight();
    float3 shadowPosition = data.positionWS + mainLight.direction * _ReceiveShadowMappingPosOffset;
#if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE)
    mainLight.shadowAttenuation = MainLightRealtimeShadow(TransformWorldToShadowCoord(shadowPosition));
#endif
    mainLight.shadowAttenuation *= HairShadow(data, mainLight.direction);
    half3 mainResult = ShadeSingleLight(surface, data, mainLight, false);
    half3 additional = 0;
#ifdef _ADDITIONAL_LIGHTS
    InputData inputData = (InputData)0;
    inputData.positionWS = data.positionWS;
    inputData.normalizedScreenSpaceUV = data.screenUV;
    #if USE_FORWARD_PLUS
        UNITY_LOOP for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
            additional += ShadeSingleLight(surface, data, GetAdditionalLight(lightIndex, data.positionWS, half4(1,1,1,1)), true);
    #endif
    uint count = GetAdditionalLightsCount();
    LIGHT_LOOP_BEGIN(count)
        additional += ShadeSingleLight(surface, data, GetAdditionalLight(lightIndex, data.positionWS, half4(1,1,1,1)), true);
    LIGHT_LOOP_END
#endif
    return CompositeAllLightResults(ShadeGI(surface, data), mainResult, additional, ShadeEmission(surface, data), surface, data);
}
half3 AdjustHSV(half3 color, float3 adjustment)
{
    float3 hsv = RgbToHsv(max(color, 0));
    hsv.x = frac(hsv.x + adjustment.x);
    hsv.y = saturate(hsv.y * adjustment.y);
    hsv.z *= max(0, adjustment.z);
    return HsvToRgb(hsv);
}
half3 ScreenRim(ToonLightingData data)
{
    if (_RimStrength <= 0 || _RimWidthPixels <= 0 || _NiloHairDepthAvailable < 0.5)
        return 0;
    float2 normalVS = TransformWorldToViewDir(data.normalWS, true).xy;
    normalVS.y *= _ProjectionParams.x;
    normalVS *= rsqrt(max(dot(normalVS, normalVS), 0.000001));
    float2 uv = data.screenUV + normalVS * _RimWidthPixels / _ScaledScreenParams.xy;
    float centerDepth = EyeDepth(SampleSceneDepth(data.screenUV));
    float neighborDepth = EyeDepth(SampleSceneDepth(saturate(uv)));
    float threshold = max(_RimDepthThreshold, 0.0001);
    float rim = smoothstep(threshold, threshold * 2, neighborDepth - centerDepth);
    float globalRim = _NiloGlobalStyleEnabled > 0.5 ? _NiloGlobalStyle.x : 1;
    return rim * _RimColor.rgb * _RimStrength * _CharacterRimMultiplier * globalRim;
}
half4 ShadeFinalColor(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    float2 uv = SurfaceUV(input);
    ClipMaterial(input, uv);
#ifdef ToonShaderIsExtraOutline
    clip(_ExtraOutlineWidth - 0.00001);
    half3 color = _ExtraOutlineColor.rgb;
#else
    ToonSurfaceData surface = InitializeSurfaceData(input, uv);
    ToonLightingData data = InitializeLightingData(input, uv);
    half3 color = ShadeAllLights(surface, data);
    #ifdef ToonShaderIsOutline
        clip(_OutlineWidth * _CharacterOutlineMultiplier - 0.00001);
        color = AdjustHSV(color * _OutlineColor.rgb, _OutlineHSV.xyz);
    #else
        color += ScreenRim(data);
    #endif
#endif
    color = AdjustHSV(color, _ColorHSV.xyz) * _CharacterTint.rgb;
    if (_NiloGlobalStyleEnabled > 0.5)
    {
        float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        color = lerp(luminance.xxx, color, _NiloGlobalStyle.z) * _NiloGlobalTint.rgb;
    }
    return half4(MixFog(color, input.fogFactor), 1);
}
half DepthOnlyFragment(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    ClipMaterial(input, SurfaceUV(input));
    return input.positionCS.z;
}
half4 DepthNormalsFragment(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    float2 uv = SurfaceUV(input);
    ClipMaterial(input, uv);
    float3 normal = SurfaceNormal(input, uv);
#if defined(_GBUFFER_NORMALS_OCT)
    return half4(PackFloat2To888(saturate(PackNormalOctQuadEncode(normal) * 0.5 + 0.5)), 0);
#else
    return half4(normal, 0);
#endif
}
float4 HairDepthFragment(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    clip(_IsHair - 0.5);
    clip(_CharacterId - 0.5);
    ClipMaterial(input, SurfaceUV(input));
    return float4(EyeDepth(input.positionCS.z), _CharacterId, 0, 0);
}
half4 EyeOverlayFragment(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    clip(min(_IsEye, _NiloHairDepthAvailable) - 0.5);
    clip(_EyeOverlayOpacity - 0.00001);
    float2 uv = GetNormalizedScreenSpaceUV(input.positionCS);
    float2 hair = ReadHair(uv);
    float eyeDepth = EyeDepth(input.positionCS.z);
    float sceneDepth = EyeDepth(SampleSceneDepth(uv));
    // Only reveal an eye occluded by this character's hair; a foreground wall still wins.
    if (!OwnHair(hair) || eyeDepth <= hair.x || eyeDepth - hair.x > _EyeOverlayMaxDistance ||
        abs(sceneDepth - hair.x) > max(0.002, hair.x * 0.0005))
        discard;
    half4 color = ShadeFinalColor(input);
    color.a = _EyeOverlayOpacity;
    return color;
}
half4 CharacterMaskFragment(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    ClipMaterial(input, SurfaceUV(input));
    half mask = SAMPLE_TEXTURE2D(_BloomMask, sampler_BaseMap, input.rawUV).r * _BloomMaskStrength;
    return half4(1, mask, 0, 1);
}
