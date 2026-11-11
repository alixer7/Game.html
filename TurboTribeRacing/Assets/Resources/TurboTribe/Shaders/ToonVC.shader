// Turbo Tribe - stylised vertex-colour shader (Built-in RP, mobile friendly).
// Wrap lighting with a soft toon band, hemispheric ambient, Blinn specular (_Gloss), rim light,
// optional world-space detail texture, real-time shadows (when enabled) and custom distance + height fog
// driven by globals (no fog keywords -> survives variant stripping on Android).
Shader "TurboTribe/ToonVC"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)
        _Scroll ("UV Scroll (xy)", Vector) = (0,0,0,0)
        _Emission ("Emission", Range(0,2)) = 0
        _RimPower ("Rim", Range(0,1)) = 0.25
        _Gloss ("Gloss", Range(0,1)) = 0
        _UseWorldUV ("World UV (0/1)", Float) = 0
        _WorldUVScale ("World UV Scale", Float) = 0.1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 200
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

            sampler2D _MainTex; float4 _MainTex_ST;
            fixed4 _Color; float4 _Scroll; half _Emission; half _RimPower; half _Gloss;
            float _UseWorldUV; float _WorldUVScale;
            float4 _TT_FogColor; float4 _TT_FogParams;
            float4 _TT_AmbientSky; float4 _TT_AmbientGround;

            struct appdata { float4 vertex:POSITION; float3 normal:NORMAL; float4 color:COLOR; float2 uv:TEXCOORD0; };
            struct v2f
            {
                float4 pos:SV_POSITION; float2 uv:TEXCOORD0; fixed4 color:COLOR; float3 wn:TEXCOORD1; float3 wp:TEXCOORD2;
                float2 uv2:TEXCOORD3;
                SHADOW_COORDS(4)
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.wp = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.wn = UnityObjectToWorldNormal(v.normal);
                float2 uv = lerp(v.uv, o.wp.xz * _WorldUVScale, _UseWorldUV);
                o.uv = TRANSFORM_TEX(uv, _MainTex) + _Scroll.xy * _Time.y;
                o.uv2 = o.wp.xz * 0.013;
                o.color = v.color * _Color;
                TRANSFER_SHADOW(o);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 n = normalize(i.wn);
                float3 l = normalize(_WorldSpaceLightPos0.xyz);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.wp);
                float atten = SHADOW_ATTENUATION(i);
                float ndl = dot(n, l);
                float wrap = saturate(ndl * 0.5 + 0.5) * lerp(0.45, 1.0, atten);
                float band = smoothstep(0.42, 0.6, wrap);
                float diff = lerp(wrap * 0.55, 0.74 + wrap * 0.26, band);
                float3 amb = lerp(_TT_AmbientGround.rgb, _TT_AmbientSky.rgb, n.y * 0.5 + 0.5);
                float rim = pow(1.0 - saturate(dot(viewDir, n)), 3.0) * _RimPower;
                float3 h = normalize(l + viewDir);
                float spec = pow(saturate(dot(n, h)), lerp(8.0, 96.0, _Gloss)) * _Gloss * atten;
                fixed4 tex = tex2D(_MainTex, i.uv);
                // macro variation breaks up large flat areas (terrain / road)
                float macro = tex2D(_MainTex, i.uv2).r * 0.25 + 0.875;
                float3 albedo = tex.rgb * i.color.rgb * lerp(1.0, macro, _UseWorldUV);
                float3 col = albedo * (_LightColor0.rgb * diff * 0.82 + amb * 0.42) + _LightColor0.rgb * (spec * 0.7 + rim * 0.6) + albedo * _Emission;
                float dist = distance(_WorldSpaceCameraPos, i.wp);
                float f = saturate((dist - _TT_FogParams.x) / max(_TT_FogParams.y - _TT_FogParams.x, 1.0)) * _TT_FogParams.w;
                col = lerp(col, _TT_FogColor.rgb, f * f * (3.0 - 2.0 * f));
                return fixed4(col, 1);
            }
            ENDCG
        }
    }
    Fallback "Legacy Shaders/VertexLit"
}
