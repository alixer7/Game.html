// Stylised water: two scrolling noise layers -> pseudo normal, fresnel sky reflection, sun glint,
// shore foam (vertex red = shallowness), custom fog. Opaque for mobile.
Shader "TurboTribe/Water"
{
    Properties
    {
        _MainTex ("Noise", 2D) = "white" {}
        _Shallow ("Shallow", Color) = (0.2,0.85,0.85,1)
        _Deep ("Deep", Color) = (0.05,0.35,0.7,1)
        _Foam ("Foam", Color) = (1,1,1,1)
        _Sky ("Sky", Color) = (0.7,0.88,1,1)
        _Scale ("Scale", Float) = 0.04
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry+1" }
        Pass
        {
            Tags { "LightMode"="ForwardBase" }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            sampler2D _MainTex; fixed4 _Shallow, _Deep, _Foam, _Sky; float _Scale;
            float4 _TT_FogColor; float4 _TT_FogParams;
            struct appdata { float4 vertex:POSITION; float4 color:COLOR; };
            struct v2f { float4 pos:SV_POSITION; float3 wp:TEXCOORD0; fixed4 color:COLOR; };
            v2f vert(appdata v)
            {
                v2f o;
                float3 wp = mul(unity_ObjectToWorld, v.vertex).xyz;
                wp.y += sin(wp.x * 0.15 + _Time.y * 1.3) * 0.12 + cos(wp.z * 0.12 + _Time.y) * 0.12;
                o.wp = wp; o.pos = mul(UNITY_MATRIX_VP, float4(wp, 1)); o.color = v.color; return o;
            }
            fixed4 frag(v2f i) : SV_Target
            {
                float2 uv = i.wp.xz * _Scale;
                float a = tex2D(_MainTex, uv + float2(_Time.x * 0.6, _Time.x * 0.3)).r;
                float b = tex2D(_MainTex, uv * 1.7 - float2(_Time.x * 0.4, -_Time.x * 0.5)).r;
                float ax = tex2D(_MainTex, uv + float2(_Time.x * 0.6 + 0.01, _Time.x * 0.3)).r;
                float az = tex2D(_MainTex, uv + float2(_Time.x * 0.6, _Time.x * 0.3 + 0.01)).r;
                float3 n = normalize(float3((a - ax) * 6.0, 1.0, (a - az) * 6.0));
                float nz = (a + b) * 0.5;
                float3 v = normalize(_WorldSpaceCameraPos - i.wp);
                float fres = pow(1.0 - saturate(dot(n, v)), 4.0);
                float3 col = lerp(_Deep.rgb, _Shallow.rgb, saturate(i.color.r * 0.9 + nz * 0.3));
                col = lerp(col, _Sky.rgb, fres * 0.55);
                float3 l = normalize(_WorldSpaceLightPos0.xyz);
                float3 h = normalize(l + v);
                col += _LightColor0.rgb * pow(saturate(dot(n, h)), 180.0) * 1.4;
                float foam = smoothstep(0.64, 0.7, nz) * 0.35 + smoothstep(0.82, 1.0, i.color.r + (nz - 0.5) * 0.3) * 0.85;
                col = lerp(col, _Foam.rgb, saturate(foam));
                float dist = distance(_WorldSpaceCameraPos, i.wp);
                float f = saturate((dist - _TT_FogParams.x) / max(_TT_FogParams.y - _TT_FogParams.x, 1.0)) * _TT_FogParams.w;
                col = lerp(col, _TT_FogColor.rgb, f * f * (3.0 - 2.0 * f));
                return fixed4(col, 1);
            }
            ENDCG
        }
    }
}
