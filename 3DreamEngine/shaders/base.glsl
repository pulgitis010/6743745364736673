#pragma language glsl3

//camera uniforms
extern highp mat4 transformProj;   //projective transformation
extern highp mat4 transform;       //model transformation
extern highp vec3 viewPos;         //camera position

//varyings
varying highp vec3 vertexPos;      //vertex position for pixel shader
varying float depth;               //depth

//shader settings
extern bool ditherAlpha;

//setting specific defines
#import globalDefines

//shader specific defines
#import vertexDefines
#import modulesDefines
#import mainDefines

#ifdef REFRACTIONS_ENABLED
extern Image tex_depth;
extern Image tex_color;
extern vec2 screenScale;
#endif

#ifdef EXPOSURE_ENABLED
extern float exposure;
#endif

#ifdef GAMMA_ENABLED
extern float gamma;
#endif

#import fog

#ifdef PIXEL

//reflection engine
#import reflections

//light function
#import lightFunction

//uniforms required by the lighting
#import lightingSystemInit

//material
extern float ior;

void effect() {
#import mainPixelPre
	
	//dither alpha
	if (ditherAlpha) {
		if (albedo.a < fract(love_PixelCoord.x * 0.37 + love_PixelCoord.y * 73.73 + depth * 3.73)) {
			discard;
		} else {
			albedo.a = 1.0;
		}
	}
	
	vec3 viewVec = normalize(viewPos - vertexPos);
	
#import vertexPixel
#import mainPixel
#import modulesPixel

#import mainPixelPost
	
#ifndef DEFERRED
	//forward lighting
	vec3 light = vec3(0.0);
#import lightingSystem
	col += light * albedo.a;
	
#import modulesPixelPost
#endif

	//calculate refractions
#ifdef REFRACTIONS_ENABLED
	vec2 startPixel = love_PixelCoord.xy * screenScale;
	
	//refract and transform back to pixel coord
	vec3 endPoint = vertexPos + normalize(refract(-viewVec, normal, ior)) * 0.25;
	vec4 endPixel = transformProj * vec4(endPoint, 1.0);
	endPixel /= endPixel.w;
	endPixel.xy = endPixel.xy * 0.5 + 0.5;
	
	//uv translation
	vec2 vec = endPixel.xy - startPixel;
	
	//depth check
	float d = Texel(tex_depth, startPixel + vec).r;
	if (d > depth) {
		vec3 nc = Texel(tex_color, startPixel + vec).xyz;
		col = mix(col, nc, albedo.a);
		albedo.a = 1.0;
	}
#endif

#ifdef FOG_ENABLED
	vec4 fogColor = getFog(depth, -viewVec, viewPos);
	col.rgb = mix(col.rgb, fogColor.rgb, fogColor.a);
#endif

	//exposure
#ifdef EXPOSURE_ENABLED
	col.rgb = vec3(1.0) - exp(-col.rgb * exposure);
#endif
	
	//gamma correction
#ifdef GAMMA_ENABLED
	col.rgb = pow(col.rgb, vec3(1.0 / gamma));
#endif
	
	//returns color
	love_Canvases[0] = vec4(col, albedo.a);
	love_Canvases[1] = vec4(depth, 1.0, 1.0, albedo.a);
	
#ifdef DEFERRED
	love_Canvases[2] = vec4(vertexPos, albedo.a);
	love_Canvases[3] = vec4(normal, albedo.a);
	love_Canvases[4] = vec4(material, albedo.a);
	love_Canvases[5] = albedo;
#else
#endif
}
#endif


#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
	vertexPos = vertex_position.xyz;
	
#import vertexVertex
#import modulesVertex
#import mainVertex
	
	//apply final vertex transform
	vertexPos = (transform * vec4(vertexPos, 1.0)).xyz;
	
	//projection transform for the vertex
	highp vec4 vPos = transformProj * vec4(vertexPos, 1.0);
	
	//extract and pass depth
	depth = vPos.z;
	
	return vPos;
}
#endif