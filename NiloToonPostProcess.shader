Shader "Hidden/NiloToon/CharacterPostProcess"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        TEXTURE2D_X(_NiloCharacterMaskTexture);
        TEXTURE2D_X(_NiloBloomTexture);
        float4 _NiloBloomSettings;
        float4 _NiloPostSettings;
        float4 _NiloBlurDirection;

        float3 ReadColor(float2 uv)
        {
            return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
        }

        half4 ExtractBloom(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 mask = SAMPLE_TEXTURE2D_X(_NiloCharacterMaskTexture, sampler_PointClamp, input.texcoord).rg;
            float weight = lerp(_NiloBloomSettings.z, _NiloBloomSettings.y * mask.g, mask.r);
            float3 color = max(0, ReadColor(input.texcoord));
            float brightness = max(color.r, max(color.g, color.b));
            float contribution = max(0, brightness - _NiloBloomSettings.x) / max(brightness, 1e-4);
            return half4(color * contribution * weight, 1);
        }

        half4 BlurBloom(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 offset = _NiloBlurDirection.xy;
            float3 color = ReadColor(input.texcoord) * 0.227027;
            color += ReadColor(input.texcoord + offset * 1.384615) * 0.316216;
            color += ReadColor(input.texcoord - offset * 1.384615) * 0.316216;
            color += ReadColor(input.texcoord + offset * 3.230769) * 0.070270;
            color += ReadColor(input.texcoord - offset * 3.230769) * 0.070270;
            return half4(color, 1);
        }

        half4 Composite(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            half4 source = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, input.texcoord);
            float3 color = source.rgb;
            if (_NiloPostSettings.w > 0)
                color += SAMPLE_TEXTURE2D_X(_NiloBloomTexture, sampler_LinearClamp, input.texcoord).rgb;
            float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
            color = lerp(luminance.xxx, color, _NiloPostSettings.x);
            color = max(0, (color - 0.18) * _NiloPostSettings.y + 0.18);
            if (_NiloPostSettings.z > 1)
            {
                // Quantize the display-range portion without clipping HDR emission before URP bloom/tonemapping.
                float steps = _NiloPostSettings.z - 1;
                color = floor(saturate(color) * steps + 0.5) / steps + max(color - 1, 0);
            }
            return half4(color, source.a);
        }
        ENDHLSL

        Pass
        {
            Name "ExtractBloom"
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment ExtractBloom
            ENDHLSL
        }
        Pass
        {
            Name "BlurBloom"
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment BlurBloom
            ENDHLSL
        }
        Pass
        {
            Name "Composite"
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Composite
            ENDHLSL
        }
    }
}
