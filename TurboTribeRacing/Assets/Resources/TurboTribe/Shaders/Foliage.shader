// Alpha-cutout, double-sided foliage cards (grass, ferns, fronds, leaves) with gentle wind sway.
// Vertex colour = tint, vertex alpha = sway weight. Texture alpha = leaf mask.
Shader "TurboTribe/Foliage"
{
    Properties
    {
        _MainTex ("Atlas", 2D) = "white" {}
        _Cutoff ("Cutoff", Range(0,1)) = 0.45
        _Wind ("Wind", Float) = 0.12
    }
    SubShader
    {
        Tags { "Queue"="AlphaTest" "RenderType"="TransparentCutout" "IgnoreProjector"="True" }
        Cull Off
        Pass
        {
            Tags { "LightMode"="ForwardBase" }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"
            sampler2D _MainTex; float4 _MainTex_ST; float _Cutoff; float _Wind;
            float4 _TT_FogColor; float4 _TT_FogParams; float4 _TT_AmbientSky; float4 _TT_AmbientGround;
            struct appdata { float4 vertex:POSITION; float3 normal:NORMAL; float4 color:COLOR; float2 uv:TEXCOORD0; };
            struct v2f { float4 pos:SV_POSITION; float2 uv:TEXCOORD0; fixed4 color:COLOR; float3 wp:TEXCOORD1; SHADOW_COORDS(2) };
            v2f vert(appdata v)
            {
                v2f o;
                float3 wp = mul(unity_ObjectToWorld, v.vertex).xyz;
                float w = v.color.a * _Wind;
                wp.x += sin(_Time.y * 1.7 + wp.z * 0.35 + wp.x * 0.2) * w;
                wp.z += cos(_Time.y * 1.3 + wp.x * 0.3) * w * 0.7;
                o.wp = wp;
                o.pos = mul(UNITY_MATRIX_VP, float4(wp, 1));
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.color = v.color;
                TRANSFER_SHADOW(o);
                return o;
            }
            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 tex = tex2D(_MainTex, i.uv);
                clip(tex.a - _Cutoff);
                float atten = SHADOW_ATTENUATION(i);
                float3 l = normalize(_WorldSpaceLightPos0.xyz);
                float lit = saturate(l.y * 0.6 + 0.45) * lerp(0.55, 1.0, atten);
                float ao = lerp(0.55, 1.0, saturate(i.uv.y * 1.4)); // darker towards the base of a card
                float3 albedo = tex.rgb * i.color.rgb;
                float3 col = albedo * (_LightColor0.rgb * lit * 0.85 + _TT_AmbientSky.rgb * 0.45) * ao;
                // translucency when looking towards the sun
                float3 v = normalize(_WorldSpaceCameraPos - i.wp);
                col += albedo * _LightColor0.rgb * pow(saturate(dot(-v, l)), 4.0) * 0.35;
                float dist = distance(_WorldSpaceCameraPos, i.wp);
                float f = saturate((dist - _TT_FogParams.x) / max(_TT_FogParams.y - _TT_FogParams.x, 1.0)) * _TT_FogParams.w;
                col = lerp(col, _TT_FogColor.rgb, f * f * (3.0 - 2.0 * f));
                return fixed4(col, 1);
            }
            ENDCG
        }
    }
    Fallback "Legacy Shaders/Transparent/Cutout/VertexLit"
}
