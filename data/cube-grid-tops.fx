float4x4 matView : WORLDVIEW;
float4x4 matViewProjection : WORLDVIEWPROJECTION;
const int2 mapSize = int2(32, 32);
texture cube_light_tex;

sampler light = sampler_state {
	Texture = (cube_light_tex);
	MipFilter = POINT;
	MinFilter = POINT;
	MagFilter = POINT;
	AddressU = WRAP;
	AddressV = WRAP;
	sRGBTexture = FALSE;
};

struct VS_OUTPUT {
	float4 pos : POSITION0;
	float2 cpos : TEXCOORD0;
	float fog : TEXCOORD4;
};

VS_OUTPUT vs_main(float4 ipos : POSITION0)
{
	VS_OUTPUT o;
	o.pos = mul(ipos, matViewProjection);
	o.cpos.xy = (floor(ipos.xz / 16) + 0.5) / mapSize;
	float eyez = mul(ipos, matView).z;
	o.fog = exp(-(eyez * eyez * 0.004));
	return o;
}

float4 ps_main(VS_OUTPUT i) : COLOR0
{
	float3 c = tex2D(light, i.cpos).rgb * 5;
	float ao = 0.005;
	return float4(ao + c * 2, 1.0);
}

technique cube_tops {
	pass P0 {
		VertexShader = compile vs_2_0 vs_main();
		PixelShader  = compile ps_2_0 ps_main();
	}
}