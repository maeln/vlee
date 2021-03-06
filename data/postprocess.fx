const float flash, fade, overlay_alpha;
const float2 noffs, nscale;
const float2 dist_offset;
const float2 viewport;
const float color_map_lerp;
const float bloom_weight[7];
const float block_thresh, line_thresh;
const float flare_amount;
const float distCoeff;
const float overlayGlitch;

texture color_tex;
sampler color_samp = sampler_state {
	Texture = (color_tex);
	MipFilter = NONE;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = BORDER;
	AddressV = BORDER;
	sRGBTexture = FALSE;
};

texture bloom_tex;
sampler bloom_samp = sampler_state {
	Texture = (bloom_tex);
	MipFilter = POINT;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = BORDER;
	AddressV = BORDER;
	sRGBTexture = FALSE;
};

texture flare_tex;
sampler flare_samp = sampler_state {
	Texture = (flare_tex);
	MipFilter = NONE;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = BORDER;
	AddressV = BORDER;
	sRGBTexture = FALSE;
};

texture spectrum_tex;
sampler spectrum_samp = sampler_state {
	Texture = (spectrum_tex);
	MipFilter = NONE;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
	sRGBTexture = FALSE;
};
sampler spectrum_samp2 = sampler_state {
	Texture = (spectrum_tex);
	MipFilter = NONE;
	MinFilter = POINT;
	MagFilter = POINT;
	AddressU = WRAP;
	AddressV = WRAP;
	sRGBTexture = FALSE;
};

texture noise_tex;
sampler noise_samp = sampler_state {
	Texture = (noise_tex);
	MipFilter = NONE;
	MinFilter = POINT;
	MagFilter = POINT;
	AddressU = WRAP;
	AddressV = WRAP;
	sRGBTexture = FALSE;
};

texture overlay_tex;
sampler overlay_samp = sampler_state {
	Texture = (overlay_tex);
	MipFilter = LINEAR;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
	sRGBTexture = TRUE;
};

texture color_map1_tex;
sampler3D color_map1_samp = sampler_state {
	Texture = (color_map1_tex);
	MipFilter = NONE;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
	AddressW = CLAMP;
	sRGBTexture = FALSE;
};

texture color_map2_tex;
sampler3D color_map2_samp = sampler_state {
	Texture = (color_map2_tex);
	MipFilter = NONE;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
	AddressW = CLAMP;
	sRGBTexture = FALSE;
};

texture lensdirt_tex;
sampler2D lensdirt_samp = sampler_state {
	Texture = (lensdirt_tex);
	MipFilter = NONE;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
	AddressW = CLAMP;
	sRGBTexture = FALSE;
};

texture vignette_tex;
sampler2D vignette_samp = sampler_state {
	Texture = (vignette_tex);
	MipFilter = NONE;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
	AddressW = CLAMP;
	sRGBTexture = TRUE;
};

struct VS_OUTPUT {
	float4 pos : POSITION;
	float2 uv  : TEXCOORD0;
	float2 npos : TEXCOORD1;
};

VS_OUTPUT vertex(float4 ipos : POSITION, float2 uv : TEXCOORD0)
{
	VS_OUTPUT Out;
	Out.pos = ipos;
	Out.uv = uv;
	Out.npos = uv * 2 - 1;
	Out.npos.x *= viewport.x / viewport.y;
	return Out;
}

float3 sample_spectrum(sampler2D tex, float2 start, float2 stop, int samples, float lod)
{
	float2 delta = (stop - start) / samples;
	float2 pos = start;
	float3 sum = 0, filter_sum = 0;
	for (int i = 0; i < samples; ++i) {
		float3 sample = tex2Dlod(tex, float4(pos, 0, lod)).rgb;
		float t = (i + 0.5) / samples;
		float3 filter = tex2Dlod(spectrum_samp, float4(t, 0, 0, 0)).rgb;
		sum += sample * filter;
		filter_sum += filter;
		pos += delta;
	}
	return sum / filter_sum;
}

float3 color_correct(float3 color)
{
#if 1
	float3 uvw = pow(color, 1.0 / 2.2) * (31.0 / 32) + 0.5 / 32;
	return lerp(tex3Dlod(color_map1_samp, float4(uvw, 0)).rgb,
	            tex3Dlod(color_map2_samp, float4(uvw, 0)).rgb,
	            color_map_lerp);
#else
	return sqrt(color);
#endif
}

float3 sample_bloom(float2 pos)
{
	float3 bloom = tex2Dlod(bloom_samp, float4(pos, 0, 0)).rgb * bloom_weight[0];
	bloom += tex2Dlod(bloom_samp, float4(pos, 0, 1)).rgb * bloom_weight[1];
	bloom += tex2Dlod(bloom_samp, float4(pos, 0, 2)).rgb * bloom_weight[1];
	bloom += tex2Dlod(bloom_samp, float4(pos, 0, 3)).rgb * bloom_weight[3];
	bloom += tex2Dlod(bloom_samp, float4(pos, 0, 4)).rgb * bloom_weight[4];
	bloom += tex2Dlod(bloom_samp, float4(pos, 0, 5)).rgb * bloom_weight[5];
	bloom += tex2Dlod(bloom_samp, float4(pos, 0, 6)).rgb * bloom_weight[6];
	return bloom;
}

float3 sample_lensflare(float2 pos)
{
	return tex2Dlod(flare_samp, float4(pos, 0, 0)).rgb * flare_amount;
}

float srgb_decode(float v)
{
	if (v <= 0.04045)
		return v / 12.92;
	else
		return pow((v + 0.055) / 1.055, 2.4);
}

float4 pixel(VS_OUTPUT In, float2 vpos : VPOS) : COLOR
{
	float2 block = floor(vpos / 16);
	float2 uv_noise = block / 64;
	uv_noise += floor(dist_offset * uv_noise) / 64;

	float haspect = viewport.x / viewport.y;
	float r2 = dot(In.npos, In.npos);
	float f = (1 + r2 * (2 * distCoeff * sqrt(r2))) / (1 + distCoeff * 4);
	float2 pos = f * (In.uv - 0.5) + 0.5;

	float2 pos2 = pos;

	float dist = pow(2 * distance(In.uv, float2(0.5, 0.5)), 2);
	const float sep = 0.03;
	float2 end = (pos - 0.5) * (1 - dist * sep * 2) + 0.5;

	// glitch some blocks and lines
	if (tex2D(noise_samp, uv_noise).r < block_thresh ||
	    tex2D(noise_samp, float2(uv_noise.y, 0)).r < line_thresh) {
		float2 dist = (frac(uv_noise) - 0.5) * 0.3;
		pos += dist * 0.1;
		end += dist * 0.12;
	}

	int samples = clamp(int(length(viewport * (end - pos) / 2)), 3, 8);
	float3 col = sample_spectrum(color_samp, pos, end, samples, 0);

	float dirt = srgb_decode(tex2Dlod(lensdirt_samp, float4(pos, 0, 0)));
	col += sample_bloom(pos) * dirt;
	col += sample_lensflare(pos) * dirt;
	col *= 1 - tex2Dlod(vignette_samp, float4(pos, 0, 0)).a;

	col = color_correct(col);

	// blend overlay
	float4 o = tex2D(overlay_samp, lerp(pos2, pos, overlayGlitch));
	col = lerp(col, o.rgb, o.a * overlay_alpha);

	// loose luma for some blocks
	if (tex2D(noise_samp, -uv_noise).r < block_thresh)
		col.rgb = col.ggg;

	// discolor block lines
	if (tex2D(noise_samp, float2(uv_noise.y, 0.0)).r * 2.75 < line_thresh)
		col.rgb = float3(0, dot(col.rgb, float3(1, 1, 1)), 0);
	if (tex2D(noise_samp, float2(0.5 - uv_noise.y, 0.0)).r * 3 < line_thresh)
		col.rgb = float2(0, dot(col.rgb, float3(1, 1, 1))).yxy;

	// interleave lines in some blocks
	if (tex2D(noise_samp, float2(0.5 - uv_noise.x, uv_noise.y)).r * 1.5 < block_thresh ||
	    tex2D(noise_samp, float2(0, uv_noise.y)).r * 2.5 < line_thresh)
	{
		col.rgb *= tex2Dlod(spectrum_samp2, float4(vpos.y / 3, 0, 0, 0)).rgb * 1.25;
	}

	// apply flashes
	col = col * fade + flash;

	// a tad of noise makes everything look cooler
	col += (tex2D(noise_samp, In.uv * nscale + noffs) - 0.5) * (1.0 / 8);

	return float4(col, 1);
}

technique postprocess {
	pass P0 {
		VertexShader = compile vs_3_0 vertex();
		PixelShader  = compile ps_3_0 pixel();
		ZEnable = False;
	}
}
