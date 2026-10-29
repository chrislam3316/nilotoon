// Independent Unity 6 / URP 17 extensions of the MIT tutorial. See IMPLEMENTATION.md.
Shader "SimpleURPToonLitExample(With Outline)"
{
    Properties
    {
        [Header(Character)]
        [ToggleUI] _IsFace("Face", Float) = 0
        [ToggleUI] _IsHair("Hair depth caster", Float) = 0
        [ToggleUI] _IsEye("Eye or eyebrow overlay", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Culling", Float) = 0
        _PerspectiveCorrection("Perspective correction", Range(0,1)) = 0
        _CharacterPivotWS("Shared pivot WS (W enables)", Vector) = (0,0,0,0)
        [HideInInspector] _CharacterId("Character ID", Float) = 0
        _CharacterTint("Character tint", Color) = (1,1,1,1)
        _CharacterFade("Dither visibility", Range(0,1)) = 1
        _CharacterRimMultiplier("Character rim multiplier", Float) = 1
        _CharacterOutlineMultiplier("Character outline multiplier", Float) = 1
        [Header(Base And Detail)]
        [MainTexture] _BaseMap("Base map", 2D) = "white" {}
        [HDR][MainColor] _BaseColor("Base color", Color) = (1,1,1,1)
        [Toggle(_UseAlphaClipping)] _UseAlphaClipping("Alpha clipping", Float) = 0
        _Cutoff("Alpha cutoff", Range(0,1)) = 0.5
        [Normal][NoScaleOffset] _BumpMap("Normal map", 2D) = "bump" {}
        _BumpScale("Normal strength", Range(0,2)) = 0
        _DetailMap("Detail color (0.5 neutral)", 2D) = "gray" {}
        _DetailStrength("Detail strength", Range(0,1)) = 0
        [NoScaleOffset] _HeightMap("Height map R", 2D) = "gray" {}
        _Parallax("Parallax scale", Range(0,0.05)) = 0
        [Header(Emission And Occlusion)]
        [ToggleUI] _UseEmission("Emission", Float) = 0
        [HDR] _EmissionColor("Emission color", Color) = (0,0,0,1)
        _EmissionMulByBaseColor("Emission multiply base", Range(0,1)) = 0
        [NoScaleOffset] _EmissionMap("Emission map", 2D) = "white" {}
        _EmissionMapChannelMask("Emission channel mask", Vector) = (1,1,1,0)
        [ToggleUI] _UseOcclusion("Occlusion", Float) = 0
        _OcclusionStrength("Occlusion strength", Range(0,1)) = 1
        [NoScaleOffset] _OcclusionMap("Occlusion map", 2D) = "white" {}
        _OcclusionMapChannelMask("Occlusion channel mask", Vector) = (1,0,0,0)
        _OcclusionRemapStart("Occlusion remap start", Range(0,1)) = 0
        _OcclusionRemapEnd("Occlusion remap end", Range(0,1)) = 1
        [Header(Toon Lighting)]
        _IndirectLightMinColor("Minimum ambient", Color) = (0.1,0.1,0.1,1)
        _IndirectLightMultiplier("Indirect light", Range(0,2)) = 1
        _DirectLightMultiplier("Direct light", Range(0,2)) = 1
        _CelShadeMidPoint("Cel midpoint", Range(-1,1)) = -0.5
        _CelShadeSoftness("Cel softness", Range(0,1)) = 0.05
        _MainLightIgnoreCelShade("Main light ignore cel", Range(0,1)) = 0
        _AdditionalLightIgnoreCelShade("Additional lights ignore cel", Range(0,1)) = 0
        _ReceiveShadowMappingAmount("Shadow strength", Range(0,1)) = 0.65
        _ShadowMapColor("Shadow color", Color) = (1,0.825,0.78,1)
        [NoScaleOffset] _ShadowTintMap("Shadow tint map", 2D) = "white" {}
        _ReceiveShadowMappingPosOffset("Shadow sample offset", Float) = 0
        [Header(Face And Hair)]
        [ToggleUI] _UseFaceSDF("Face SDF", Float) = 0
        [NoScaleOffset] _FaceShadowMap("Face angle threshold R", 2D) = "gray" {}
        _FaceShadowSoftness("Face shadow softness", Range(0.001,0.49)) = 0.05
        _FaceForwardWS("Head forward WS", Vector) = (0,0,1,0)
        _FaceRightWS("Head right WS", Vector) = (1,0,0,0)
        _HairShadowStrength("Hair shadow strength", Range(0,1)) = 0
        _HairShadowOffsetPixels("Hair shadow offset pixels", Range(0,64)) = 8
        _HairShadowMaxDistance("Hair to face maximum distance", Float) = 0.3
        _EyeOverlayOpacity("Eye overlay opacity", Range(0,1)) = 0
        _EyeOverlayMaxDistance("Hair to eye maximum distance", Float) = 0.3
        [Header(Specular And MatCap)]
        _SpecularStrength("GGX strength", Range(0,2)) = 0
        _Metallic("Metallic", Range(0,1)) = 0
        _Roughness("Roughness", Range(0.02,1)) = 0.5
        [NoScaleOffset] _MaterialMask("R metallic G roughness B specular", 2D) = "white" {}
        [NoScaleOffset] _MatCapMap("MatCap", 2D) = "black" {}
        [HDR] _MatCapColor("MatCap tint", Color) = (1,1,1,1)
        _MatCapStrength("MatCap strength", Range(0,2)) = 0
        [Enum(Add,0,Multiply,1,Replace,2)] _MatCapMode("MatCap blend", Float) = 0
        [HDR] _SSSColor("Backlight color", Color) = (1,0.4,0.3,1)
        _SSSStrength("Backlight SSS approximation", Range(0,1)) = 0
        [Header(Screen Depth Rim)]
        [HDR] _RimColor("Rim color", Color) = (1,1,1,1)
        _RimStrength("Rim strength", Range(0,2)) = 0
        _RimWidthPixels("Rim width pixels", Range(0,16)) = 2
        _RimDepthThreshold("Rim depth threshold", Float) = 0.05
        [Header(Outline)]
        _OutlineWidth("Outline width pixels", Range(0,8)) = 1
        _OutlineColor("Outline tint", Color) = (0.5,0.5,0.5,1)
        [NoScaleOffset] _OutlineMask("Outline width R", 2D) = "white" {}
        [ToggleUI] _UseSmoothOutlineNormal("Use baked UV4 smooth normals", Float) = 0
        _OutlineZOffset("Outline depth offset", Range(0,1)) = 0.0001
        [NoScaleOffset] _OutlineZOffsetMaskTex("Depth mask (black applies)", 2D) = "black" {}
        _OutlineZOffsetMaskRemapStart("Depth mask remap start", Range(0,1)) = 0
        _OutlineZOffsetMaskRemapEnd("Depth mask remap end", Range(0,1)) = 1
        _ExtraOutlineWidth("Extra outline pixels", Range(0,16)) = 0
        [HDR] _ExtraOutlineColor("Extra outline color", Color) = (0,0,0,1)
        [Header(Color And Dissolve)]
        _ColorHSV("Hue shift / saturation / value", Vector) = (0,1,1,0)
        _OutlineHSV("Outline hue / saturation / value", Vector) = (0,1,1,0)
        [NoScaleOffset] _DissolveMap("Dissolve noise R", 2D) = "white" {}
        _DissolveAmount("Dissolve", Range(0,1)) = 0
        _DissolveEdgeWidth("Dissolve edge", Range(0.001,0.2)) = 0.03
        [HDR] _DissolveEdgeColor("Dissolve edge color", Color) = (3,1,0,1)
        [NoScaleOffset] _BloomMask("Character glow mask R", 2D) = "white" {}
        _BloomMaskStrength("Character glow mask strength", Range(0,1)) = 1
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        HLSLINCLUDE
        #pragma target 4.5
        #pragma shader_feature_local_fragment _UseAlphaClipping
        #pragma multi_compile_instancing
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull [_Cull] ZWrite On ZTest LEqual Blend One Zero
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment ShadeFinalColor
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
                        #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front ZWrite On ZTest LEqual
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment ShadeFinalColor
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
                        #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #define ToonShaderIsOutline
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            Cull [_Cull] ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #define ToonShaderApplyShadowBiasFix
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            Cull [_Cull] ZWrite On ZTest LEqual ColorMask R
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment DepthOnlyFragment

            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormalsOnly"
            Tags { "LightMode"="DepthNormalsOnly" }
            Cull [_Cull] ZWrite On ZTest LEqual
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "HairDepth"
            Tags { "LightMode"="NiloHairDepth" }
            Cull [_Cull] ZWrite On ZTest LEqual
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment HairDepthFragment

            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "EyeOverlay"
            Tags { "LightMode"="NiloEyeOverlay" }
            Cull [_Cull] ZWrite Off ZTest Always Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment EyeOverlayFragment
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
                        #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "CharacterMask"
            Tags { "LightMode"="NiloCharacterMask" }
            Cull [_Cull] ZWrite Off ZTest LEqual
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment CharacterMaskFragment

            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ExtraOutline"
            Tags { "LightMode"="NiloExtraOutline" }
            Cull Front ZWrite Off ZTest LEqual
            HLSLPROGRAM
            #pragma vertex VertexShaderWork
            #pragma fragment ShadeFinalColor
            #pragma multi_compile_fog
            #define ToonShaderIsOutline
            #define ToonShaderIsExtraOutline
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
