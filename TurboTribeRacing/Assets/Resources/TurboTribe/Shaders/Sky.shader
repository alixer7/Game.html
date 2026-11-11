// Vertex-coloured unlit sky dome with optional sun glow.
Shader "TurboTribe/Sky"
{
    Properties { _SunDir ("Sun Dir", Vector) = (0.3,0.6,0.5,0) _SunColor ("Sun Color", Color) = (1,0.95,0.8,1) }
    SubShader
    {
        Tags { "RenderType"="Background" "Queue"="Background" "PreviewType"="Skybox" }
        Cull Front ZWrite Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            float4 _SunDir; fixed4 _SunColor;
            struct appdata { float4 vertex:POSITION; float4 color:COLOR; };
            struct v2f { float4 pos:SV_POSITION; fixed4 color:COLOR; float3 dir:TEXCOORD0; };
            v2f vert(appdata v)
            {
                v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.color = v.color; o.dir = normalize(v.vertex.xyz); return o;
            }
            fixed4 frag(v2f i) : SV_Target
            {
                float s = saturate(dot(normalize(i.dir), normalize(_SunDir.xyz)));
                float glow = pow(s, 64.0) * 1.2 + pow(s, 8.0) * 0.25;
                return fixed4(i.color.rgb + _SunColor.rgb * glow, 1);
            }
            ENDCG
        }
    }
}
