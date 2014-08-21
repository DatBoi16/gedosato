/*
	 -Volumetric SSAO-
	Implemented by Tomerk for OBGE
	Adapted and tweaked for Dark Souls by Durante
	Modified by Asmodean, for accurate occlusion distance, and dynamic positional depth offsets, for Dark Souls
	Modified further for inclusion in DSfix 2.2 (depth-dependent thickness model) and adapted for Dark Souls 2 by Durante. Will it ever stop?
*/

/***User-controlled variables***/
#define N_SAMPLES 32 //number of samples, currently do not change.

extern float aoRadiusMultiplier = 0.2; //Linearly multiplies the radius of the AO Sampling
extern float ThicknessModel = 6; //units in space the AO assumes objects' thicknesses are
extern float FOV = 75; //Field of View in Degrees
extern float luminosity_threshold = 0.5;

#ifndef USE_SRGB
#define USE_SRGB true
#endif

#ifndef SCALE
#define SCALE 1.0
#endif

#ifndef SSAO_STRENGTH_LOW
#ifndef SSAO_STRENGTH_MEDIUM
#ifndef SSAO_STRENGTH_HIGH
#define SSAO_STRENGTH_MEDIUM 1
#endif
#endif
#endif

#ifdef SSAO_STRENGTH_LOW
extern float aoClamp = 0.6;
extern float aoStrengthMultiplier = 0.9;
#endif

#ifdef SSAO_STRENGTH_MEDIUM
extern float aoClamp = 0.3;
extern float aoStrengthMultiplier = 1.5;
#endif

#ifdef SSAO_STRENGTH_HIGH
extern float aoClamp = 0.1;
extern float aoStrengthMultiplier = 2.0;
#endif

#define LUMINANCE_CONSIDERATION //comment this line to not take pixel brightness into account

/***End Of User-controlled Variables***/
static float2 rcpres = PIXEL_SIZE;
static float aspect = rcpres.y/rcpres.x;
static const float nearZ = 1;
static const float farZ = 3500;
static const float2 g_InvFocalLen = { tan(0.5f*radians(FOV)) / rcpres.y * rcpres.x, tan(0.5f*radians(FOV)) };
static const float depthRange = nearZ-farZ;

texture2D depthTex2D;
sampler depthSampler = sampler_state
{
	texture = <depthTex2D>;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU  = Mirror;
	AddressV  = Mirror;
	SRGBTexture=FALSE;
};

texture2D frameTex2D;
sampler frameSampler = sampler_state
{
	texture = <frameTex2D>;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = LINEAR;
	AddressU  = Clamp;
	AddressV  = Clamp;
	SRGBTexture = USE_SRGB;
};

texture2D prevPassTex2D;
sampler passSampler = sampler_state
{
	texture = <prevPassTex2D>;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = LINEAR;
	AddressU  = Clamp;
	AddressV  = Clamp;
	SRGBTexture=FALSE;
};

struct VSOUT
{
	float4 vertPos : POSITION0;
	float2 UVCoord : TEXCOORD0;
};

struct VSIN
{
	float4 vertPos : POSITION0;
	float2 UVCoord : TEXCOORD0;
};


VSOUT FrameVS(VSIN IN)
{
	VSOUT OUT;
	float4 pos=float4(IN.vertPos.x, IN.vertPos.y, IN.vertPos.z, 1.0f);
	OUT.vertPos=pos;
	float2 coord=float2(IN.UVCoord.x, IN.UVCoord.y);
	OUT.UVCoord=coord;
	return OUT;
}

static float2 sample_offset[N_SAMPLES] =
{
	 float2(1.00f, 1.00f),
	 float2(-1.00f, -1.00f),
	 float2(-1.00f, 1.00f),
	 float2(1.00f, -1.00f),

	 float2(1.00f, 0.00f),
	 float2(-1.00f, 0.00f),
	 float2(0.00f, 1.00f),
	 float2(0.00f, -1.00f),

	 float2(1.00f, 0.00f),
	 float2(-1.00f, 0.00f),
	 float2(0.00f, 1.00f),
	 float2(0.00f, -1.00f),

	 float2(1.00f, 1.00f),
	 float2(-1.00f, -1.00f),
	 float2(-1.00f, 1.00f),
	 float2(1.00f, -1.00f),
	 
	 float2(1.00f, 0.00f),
	 float2(-1.00f, 0.00f),
	 float2(0.00f, 1.00f),
	 float2(0.00f, -1.00f),

	 float2(1.00f, 0.00f),
	 float2(-1.00f, 0.00f),
	 float2(0.00f, 1.00f),
	 float2(0.00f, -1.00f),

	 float2(1.00f, 1.00f),
	 float2(-1.00f, -1.00f),
	 float2(-1.00f, 1.00f),
	 float2(1.00f, -1.00f),
	 
	 float2(1.00f, 1.00f),
	 float2(-1.00f, -1.00f),
	 float2(-1.00f, 1.00f),
	 float2(1.00f, -1.00f)
};

static float sample_radius[N_SAMPLES] =
{
	0.20f, 0.20f,
	0.20f, 0.20f,
	0.20f, 0.20f,
	0.20f, 0.20f,
	
	0.20f, 0.20f,
	0.20f, 0.20f,
	0.20f, 0.20f,
	0.20f, 0.20f,
	
	0.20f, 0.20f,
	0.20f, 0.20f,
	0.20f, 0.20f,
	0.20f, 0.20f,
	
	0.20f, 0.20f,
	0.20f, 0.20f,
	0.20f, 0.20f,
	0.20f, 0.20f
};

float2 rand(in float2 uv : TEXCOORD0) {
	float noiseX = (frac(sin(dot(uv, float2(12.9898,78.233)*2.0)) * 43758.5453));
	float noiseY = sqrt(1-noiseX*noiseX);
	return float2(noiseX, noiseY);
}

//#define NEW_SSAO
//#define SHOW_SSAO

#ifdef USE_HWDEPTH
float2 readDepth(in float2 coord : TEXCOORD0)
{
	float z = tex2D(depthSampler, coord).r; // Depth is stored in the red component
	return (2.0 * nearZ) / (farZ + nearZ - z * (farZ - nearZ));
}
#else
float2 readDepth(in float2 coord : TEXCOORD0)
{
	float4 col = tex2D(depthSampler, coord);
	#ifdef NEW_SSAO
	float posZ = ((col.x) + (col.y)*255.0 + (col.z)*(255.0*255.0));
	// (2.0f * nearZ) / (sumZ - depth * rangeZ);
	float depth = abs(posZ)/(256.0);
	return float2(depth, col.w);
	//return float2((2.0 * nearZ) / (farZ + nearZ - depth * (farZ - nearZ)), col.w);
	#else
	float posZ = ((1 - col.x) + (1 - col.y)*255.0 + (1 - col.z)*(255.0*255.0));
	return float2(pow(posZ / (5 * 256.0*256.0) + 1.0, 8.0) - 1.0, col.w);
	#endif
}
#endif

float3 getPosition(in float2 uv : TEXCOORD0, in float eye_z : POSITION0) {
   uv = (uv * float2(2.0, -2.0) - float2(1.0, -1.0));
   float3 pos = float3(uv * g_InvFocalLen * eye_z, eye_z );
   return pos;
}

float3 normalFromDepth(float depth, float2 texcoords) {
	const float2 offset1 = float2(0.0, PIXEL_SIZE.y);
	const float2 offset2 = float2(PIXEL_SIZE.x, 0.0);

	float depth1 = readDepth(texcoords + offset1).x;
	float depth2 = readDepth(texcoords + offset2).x;

	float3 p1 = float3(offset1, depth1 - depth);
	float3 p2 = float3(offset2, depth2 - depth);

	float3 normal = cross(p1, p2);
	return normalize(normal);
}

#ifndef NEW_SSAO
float4 ssao_Main(VSOUT IN) : COLOR0
{
	clip(1/SCALE-IN.UVCoord.x);
	clip(1/SCALE-IN.UVCoord.y);	
	IN.UVCoord.xy *= SCALE;

	float2 d2 = readDepth(IN.UVCoord);
	if(d2.y < 0.1) return float4(1.0,1.0,1.0,1.0);
	float depth = d2.x;

	#ifdef NORM_WITHOUT_DD
	float3 norm = normalFromDepth(depth, IN.UVCoord);
	#else
	float3 pos = getPosition(IN.UVCoord, depth);
	float3 dx = ddx(pos);
	float3 dy = ddy(pos);
	float3 norm = normalize(cross(dx, dy));
	norm.y *= -1;
	#endif

	float sample_depth;

	float ao = 0.0;
	float s = 0.0;

	float2 rand_vec = rand(IN.UVCoord);
	float2 sample_vec_divisor = g_InvFocalLen*depth*depthRange/(aoRadiusMultiplier*5000*rcpres);
	float2 sample_center = IN.UVCoord + norm.xy/sample_vec_divisor*float2(1.0f,aspect);
	float sample_center_depth = depth*depthRange + norm.z*aoRadiusMultiplier*7;
	
	for(int i = 0; i < N_SAMPLES; i++)
	{
		float2 sample_vec = reflect(sample_offset[i], rand_vec);
		sample_vec /= sample_vec_divisor;
		float2 sample_coords = sample_center + sample_vec*float2(1.0f,aspect);
		
		float curr_sample_radius = sample_radius[i]*aoRadiusMultiplier*10;
		float curr_sample_depth = depthRange*readDepth(sample_coords);
		
		ao += clamp(0,curr_sample_radius+sample_center_depth-curr_sample_depth,2*curr_sample_radius);
		ao -= clamp(0,curr_sample_radius+sample_center_depth-curr_sample_depth-ThicknessModel,2*curr_sample_radius);
		s += 2.0*curr_sample_radius;
	}

	ao /= s;
	
	// adjust for close and far away
	if(depth<0.065f) ao = lerp(ao, 0.0f, (0.065f-depth)*13.3);

	ao = 1.0f-ao*aoStrengthMultiplier;

	return float4(ao, ao, ao, depth);
	//return float4(depth, depth, depth, depth);
	//return float4(norm.x,norm.y,norm.z,depth);
}
#else
float4 ssao_Main(VSOUT IN) : COLOR0
{
	const float total_strength = 1.0;
	const float base = 1.2;

	const float area = 3.0;
	const float falloff = 0.001;

	const float radius = 25.0;

	const int samples = 16;
	float3 sample_sphere[samples] = {
		float3(0.5381, 0.1856, -0.4319), float3(0.1379, 0.2486, 0.4430),
		float3(0.3371, 0.5679, -0.0057), float3(-0.6999, -0.0451, -0.0019),
		float3(0.0689, -0.1598, -0.8547), float3(0.0560, 0.0069, -0.1843),
		float3(-0.0146, 0.1402, 0.0762), float3(0.0100, -0.1924, -0.0344),
		float3(-0.3577, -0.5301, -0.4358), float3(-0.3169, 0.1063, 0.0158),
		float3(0.0103, -0.5869, 0.0046), float3(-0.0897, -0.4940, 0.3287),
		float3(0.7119, -0.0154, -0.0918), float3(-0.0533, 0.0596, -0.5411),
		float3(0.0352, -0.0631, 0.5460), float3(-0.4776, 0.2847, -0.0271)
	};

	float noise = sin(dot(IN.UVCoord, float2(12.9898, 78.233)*2.0)) * 43758.5453;
	float3 random;
	random.x = frac(noise)*2.0 - 1.0;
	random.y = frac(noise*1.2154)*2.0 - 1.0;
	random.z = frac(noise*1.3453)*2.0 - 1.0;

	float2 d2 = readDepth(IN.UVCoord);
	if(d2.y < 0.1) return float4(1.0, 1.0, 1.0, 1.0);
	float depth = d2.x;

	float3 position = float3(IN.UVCoord, depth);
	float3 normal = normalFromDepth(depth, IN.UVCoord);
	normal.z = -normal.z;

	float radius_depth = radius / pow(depth,1.3);
	float occlusion = 0.0;
	for(int i = 0; i < samples; i++) {
		float3 ray = radius_depth * reflect(sample_sphere[i], random);
		float3 hemi_ray = position + sign(dot(ray, normal)) * ray;

		float occ_depth = readDepth(saturate(hemi_ray.xy)).r;
		float difference = depth - occ_depth;

		occlusion += step(falloff, difference) * (1.0 - smoothstep(falloff, area, difference));
	}

	float ao = saturate(base - total_strength * occlusion * (1.0 / samples));

	//return float4(normal.x, normal.y, normal.z, depth);
	return float4(ao, ao, ao, depth);
}
#endif

#ifdef BLUR_SHARP
float4 HBlur( VSOUT IN ) : COLOR0 {
	float4 sample = tex2D(passSampler, IN.UVCoord);
	float blurred = sample.r*2;
	float depth = sample.a;
	float divide = 2.0;

	float4 left = tex2D(passSampler, IN.UVCoord - float2(rcpres.x, 0));
	float lpower = saturate(ThicknessModel - abs(left.a - depth));
	blurred += lpower*left.r;
	divide += lpower;

	float4 right = tex2D(passSampler, IN.UVCoord + float2(rcpres.x, 0));
	float rpower = saturate(ThicknessModel - abs(right.a - depth));
	blurred += rpower*left.r;
	divide += rpower;

	return float4(blurred/divide, 0, 0, depth);
}
float4 VBlur( VSOUT IN ) : COLOR0 {
	float4 sample = tex2D(passSampler, IN.UVCoord);
	float blurred = sample.r*2;
	float depth = sample.a;
	float divide = 2.0;

	float4 top = tex2D(passSampler, IN.UVCoord - float2(0, rcpres.y));
	float tpower = saturate(ThicknessModel - abs(top.a - depth));
	blurred += tpower*top.r;
	divide += tpower;

	float4 bottom = tex2D(passSampler, IN.UVCoord + float2(0, rcpres.y));
	float bpower = saturate(ThicknessModel - abs(bottom.a - depth));
	blurred += bpower*bottom.r;
	divide += bpower;

	return float4(blurred / divide, 0, 0, depth);
}
#else // BLUR_GAUSSIAN
float4 HBlur(VSOUT IN) : COLOR0{
	float4 sample = tex2D(passSampler, IN.UVCoord);
	#ifdef SHOW_SSAO
	return sample;
	#endif
	float color = sample.r;

	float blurred = color*0.2270270270;
	blurred += tex2D(passSampler, IN.UVCoord + float2(rcpres.x*1.3846153846, 0)).r * 0.3162162162;
	blurred += tex2D(passSampler, IN.UVCoord - float2(rcpres.x*1.3846153846, 0)).r * 0.3162162162;
	blurred += tex2D(passSampler, IN.UVCoord + float2(rcpres.x*3.2307692308, 0)).r * 0.0702702703;
	blurred += tex2D(passSampler, IN.UVCoord - float2(rcpres.x*3.2307692308, 0)).r * 0.0702702703;

	return float4(blurred, 0, 0, sample.a);
}

float4 VBlur(VSOUT IN) : COLOR0{
	float4 sample = tex2D(passSampler, IN.UVCoord);
	#ifdef SHOW_SSAO
	return sample;
	#endif
	float color = sample.r;

	float blurred = color*0.2270270270;
	blurred += tex2D(passSampler, IN.UVCoord + float2(0, rcpres.y*1.3846153846)).r * 0.3162162162;
	blurred += tex2D(passSampler, IN.UVCoord - float2(0, rcpres.y*1.3846153846)).r * 0.3162162162;
	blurred += tex2D(passSampler, IN.UVCoord + float2(0, rcpres.y*3.2307692308)).r * 0.0702702703;
	blurred += tex2D(passSampler, IN.UVCoord - float2(0, rcpres.y*3.2307692308)).r * 0.0702702703;

	return float4(blurred, 0, 0, sample.a);
}
#endif // blur type

float4 Combine( VSOUT IN ) : COLOR0 {
	float4 color = tex2D(frameSampler, IN.UVCoord);
	float4 aoSample = tex2D(passSampler, IN.UVCoord/SCALE);
	float ao = clamp(aoSample.r, aoClamp, 1.0);

	#ifdef LUMINANCE_CONSIDERATION
	float luminance = (color.r*0.2125f)+(color.g*0.7154f)+(color.b*0.0721f);
	float white = 1.0f;
	float black = 0.0f;

	luminance = clamp(max(black,luminance-luminosity_threshold)+max(black,luminance-luminosity_threshold)+max(black,luminance-luminosity_threshold),0.0,1.0);
	ao = lerp(ao,white,luminance);
	#endif

	color.rgb *= ao;

	#ifdef SHOW_SSAO
	return aoSample;
	#endif
	return color;
}

technique t0
{
	pass p0
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 ssao_Main();	
	}
	pass p1
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 HBlur();
	}
	pass p2
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 VBlur();
	}
	pass p3
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 Combine();
	}
}