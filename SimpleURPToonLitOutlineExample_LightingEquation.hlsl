// Independent toon extensions; URP's built-in BRDF supplies the optional GGX highlight.
#pragma once

half3 ToonDiffuseColor(ToonSurfaceData surfaceData)
{
    half metallic = saturate(surfaceData.metallic) * saturate(_SpecularStrength);
    return surfaceData.albedo * (1.0h - metallic);
}

half ToonFaceSDFLighting(ToonSurfaceData surfaceData, half3 lightDirectionWS)
{
    float3 forward = _FaceForwardWS.xyz;
    forward = dot(forward, forward) > 1e-6 ? normalize(forward) : float3(0, 0, 1);
    float3 right = _FaceRightWS.xyz - forward * dot(_FaceRightWS.xyz, forward);
    if (dot(right, right) < 1e-6)
    {
        float3 up = abs(forward.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0);
        right = cross(up, forward);
    }
    right = normalize(right);

    float2 planarLight = float2(dot(lightDirectionWS, right), dot(lightDirectionWS, forward));
    planarLight = dot(planarLight, planarLight) > 1e-6 ? normalize(planarLight) : float2(0, 1);
    float angle = acos(clamp(planarLight.y, -1.0, 1.0)) * INV_PI;
    half field = planarLight.x >= 0 ? surfaceData.faceShadow : surfaceData.faceShadowMirrored;
    half softness = clamp(_FaceShadowSoftness, 0.0001h, 0.49h);
    // Keep front lighting fully lit and back lighting fully dark, including black/white texels.
    field = lerp(softness, 1.0h - softness, saturate(field));
    return smoothstep(angle - softness, angle + softness, field);
}

half3 ShadeGI(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    half3 averageSH = max(_IndirectLightMinColor.rgb, SampleSH(half3(0, 0, 0)));
    half indirectOcclusion = lerp(1.0h, surfaceData.occlusion, 0.5h);
    return ToonDiffuseColor(surfaceData) * averageSH * indirectOcclusion * _IndirectLightMultiplier;
}

half3 ShadeSingleLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
    half3 normalWS = lightingData.normalWS;
    half NoL = dot(normalWS, light.direction);
    half softness = max(_CelShadeSoftness, 0.0001h);
    half lit = smoothstep(_CelShadeMidPoint - softness, _CelShadeMidPoint + softness, NoL);
    lit *= surfaceData.occlusion;
    if (_IsFace > 0.5)
    {
        lit = _UseFaceSDF > 0.5
            ? ToonFaceSDFLighting(surfaceData, light.direction) * surfaceData.occlusion
            : lerp(0.5h, 1.0h, lit);
    }

    half ignoreCel = isAdditionalLight ? _AdditionalLightIgnoreCelShade : _MainLightIgnoreCelShade;
    lit = lerp(lit, surfaceData.occlusion, saturate(ignoreCel));
    half globalShadowStrength = _NiloGlobalStyleEnabled > 0.5 ? _NiloGlobalStyle.y : 1.0h;
    half3 globalShadowTint = _NiloGlobalStyleEnabled > 0.5 ? _NiloGlobalShadowTint.rgb : half3(1, 1, 1);
    half shadow = lerp(1.0h, light.shadowAttenuation, saturate(_ReceiveShadowMappingAmount * globalShadowStrength));
    half3 diffuse = ToonDiffuseColor(surfaceData) * lerp(_ShadowMapColor.rgb * surfaceData.shadowTint * globalShadowTint, half3(1, 1, 1), lit * shadow);
    half3 extraLight = 0;

    if (_SpecularStrength > 0 && surfaceData.specularMask > 0)
    {
        BRDFData brdf;
        half alpha = surfaceData.alpha;
        InitializeBRDFData(surfaceData.albedo, saturate(surfaceData.metallic), half3(0.04h, 0.04h, 0.04h),
            1.0h - clamp(surfaceData.roughness, 0.02h, 1.0h), alpha, brdf);
        half specular = DirectBRDFSpecular(brdf, normalWS, light.direction, lightingData.viewDirectionWS);
        extraLight += brdf.specular * specular * saturate(NoL) * shadow
            * _SpecularStrength * saturate(surfaceData.specularMask);
    }

    // shortcut: this is back lighting without thickness, use a transmission model for physical skin.
    half backLight = saturate(-NoL);
    extraLight += surfaceData.albedo * _SSSColor.rgb * (_SSSStrength * backLight * backLight * shadow);

    half attenuation = min(4.0h, light.distanceAttenuation) * (isAdditionalLight ? 0.25h : 1.0h);
    return (diffuse + extraLight) * saturate(light.color) * attenuation * _DirectLightMultiplier;
}

half3 ShadeEmission(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    return lerp(surfaceData.emission, surfaceData.emission * surfaceData.albedo, _EmissionMulByBaseColor);
}

half3 CompositeAllLightResults(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult,
    half3 emissionResult, ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // Retain the tutorial's toon composition rather than adding indirect and direct diffuse together.
    half3 color = max(indirectResult, mainLightResult + additionalLightSumResult);
    if (_MatCapStrength > 0)
    {
        half3 normalVS = TransformWorldToViewDir(lightingData.normalWS, true);
        float2 matcapUV = normalVS.xy * 0.5 + 0.5;
        half3 matcap = SAMPLE_TEXTURE2D(_MatCapMap, sampler_LinearClamp, matcapUV).rgb * _MatCapColor.rgb;
        if (_MatCapMode < 0.5)
            color += matcap * _MatCapStrength;
        else if (_MatCapMode < 1.5)
            color *= lerp(half3(1, 1, 1), matcap, saturate(_MatCapStrength));
        else
            color = lerp(color, matcap, saturate(_MatCapStrength));
    }
    return color + emissionResult;
}
