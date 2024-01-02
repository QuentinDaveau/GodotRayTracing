#[compute]
#version 450
#pragma vscode_glsllint_stage : comp

struct Sphere
{
	vec3 	center;
	float 	radius;
	vec4 	color;
	float 	emission;
	float 	specular;
	float 	clearcoat;
	float 	subsurface_scattering;
};

struct Plane
{
	vec3 	location;
	float 	emission;
	vec3 	normal;
	float 	specular;
	vec2	scale;
	float 	clearcoat;
	float 	subsurface_scattering;
	vec4 	color;
};

struct Ray 
{
	vec3 origin;
	vec3 direction;
	vec3 color;
};

struct RayHit
{
	vec3 location;
	vec3 normal;
	float dist;
	vec3 color;
	float specular;
};


// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D m_renderedImage;

layout(set = 0, binding = 1, std430) restrict buffer DataBuffer {
	float time;
}
m_dataBuffer;

layout(set = 0, binding = 2, std430) restrict buffer CameraBuffer {
	mat4 transform;
	mat4 projection;
}
m_cameraBuffer;


layout(set = 0, binding = 3, std430) restrict buffer LightBuffer {
	vec3 direction;
	float intensity;
}
m_lightBuffer;


layout(set = 0, binding = 4, std430) restrict buffer SpheresBuffer {
	Sphere spheres[];
}
m_spheresBuffer;



layout(set = 0, binding = 5, std430) restrict buffer PlanesBuffer {
	Plane planes[];
}
m_planesBuffer;



// ------------- Constants -----------------
float Infinity = 9999999.0;
float Golden = 3.88322207745093;

vec3 SkyLow = vec3(0.6, 0.4, 0.2);
vec3 SkyMiddle = vec3(0.35, 0.7, 0.8);
vec3 SkyHigh = vec3(0.7, 0.8, 0.9);
vec3 LightColor = vec3(100.0);

int BounceTests = 5;
int RaysPerPixel = 100;

float Random(inout float seed)
{
	float rand = sin(seed * 15848.0);
	seed = mod(seed + rand, 10.0) + 0.00001;
	// val *= (val + 1951439) * (val + 1252395) * (val + 5215922);
	return fract(rand);
}


float RandomM11(inout float seed)
{
	return (Random(seed) * 2.0) - 1.0;
}



void TestSphereHit(Ray ray, Sphere sphere, inout RayHit bestHit)
{
	// Calculate distance along the ray where the sphere is intersected
	float radSqr = sphere.radius * sphere.radius;
	vec3 direction = sphere.center - ray.origin;
	float proj = dot(ray.direction, direction);
	if (proj < 0.0)
		return;
	float projDistSqr = dot(direction, direction) - proj * proj; // Dot a vector by itself allows to get its amplitude squared
	if (projDistSqr > radSqr)
		return;
	float projDist = sqrt(radSqr - projDistSqr);
	float dist = proj - projDist > 0.0 ? proj - projDist : proj + projDist;

	// Successful Hit
	if (dist > 0.0 && dist < bestHit.dist)
	{
		bestHit.dist = dist;
		bestHit.location = ray.origin + dist * ray.direction;
		bestHit.normal = normalize(bestHit.location - sphere.center);
		bestHit.color = sphere.color.xyz;
		bestHit.specular = sphere.specular;
	}
}



void TestPlaneHit(Ray ray, Plane plane, inout RayHit bestHit)
{
	// see https://stackoverflow.com/questions/23975555/how-to-do-ray-plane-intersection
	float denom = -dot(plane.normal, ray.direction);
	if (denom > 0.00001) // We only want to hit from the front side of the plane
	{
		float origDistToPlane = dot(ray.origin - plane.location, plane.normal);
		float hitDist = origDistToPlane / denom;

		// hitDist should always be valid
		if (hitDist > 0.0 && hitDist < bestHit.dist)
		{
			bestHit.dist = hitDist;
			bestHit.location = ray.origin + ray.direction * hitDist;
			bestHit.normal = plane.normal;
			bestHit.color = plane.color.xyz;
			bestHit.specular = plane.specular;
		}
	}
}




vec3 GetSkyColorForDirection(vec3 direction)
{
	float amount = dot(vec3(0.0, 1.0, 0.0), direction);
	float lightAmount = pow(max(dot(-direction, m_lightBuffer.direction), 0.0), 100.0);
	if (amount >= 0.0)
		return mix(mix(SkyMiddle, SkyHigh, amount * amount), LightColor, lightAmount);
	else
		return mix(SkyMiddle, SkyLow, amount * amount);
}



bool TestHit(Ray ray, inout RayHit hit)
{
	hit.dist = Infinity;
	hit.normal = vec3(0.0);

	// Testing spheres
	for (int i = 0; i < m_spheresBuffer.spheres.length(); i++)
	{
		TestSphereHit(ray, m_spheresBuffer.spheres[i], hit);
	}

	// Testing the planes
	for (int i = 0; i < m_planesBuffer.planes.length(); i++)
	{
		TestPlaneHit(ray, m_planesBuffer.planes[i], hit);
	}

	return hit.normal != vec3(0.0);
}



vec3 GetFibDir(int i, int samples, vec3 normal, float rand)
{
	// Fibonacci
	float randi = i * (1.0 - rand * 0.01);
	float y = 1.0 - ((randi / float(samples)) * 2.0);  // y goes from 1 to 0
	float radius = sqrt(1 - y * y);
	float theta = Golden * randi;
	float x = cos(theta) * radius;
	float z = sin(theta) * radius;

	vec3 vec = vec3(x, y, z);
	return vec * sign(dot(normal, vec));
}




float randNormDist(inout float rand)
{
	float theta = 2.0 * 3.1415926 * Random(rand);
	float rho = sqrt(-2.0 * (log(Random(rand) * 0.999 + 0.001)));
	return rho * cos(theta);
}



vec3 GetRandDir(vec3 normal, inout float rand)
{
	// float x = RandomM11(rand);
	// float y = RandomM11(rand) * ((cos(x * 3.1415926) / 2.0) + 1.0);
	// float z = sign(RandomM11(rand)) * ((cos((abs(x) + abs(y)) * 3.1415926) / 2.0) + 1.0);
	// vec3 vec = vec3(x, y, z);
	vec3 vec = normalize(vec3(RandomM11(rand), RandomM11(rand), RandomM11(rand)));
	return vec * sign(dot(normal, vec));
}



vec3 CastRay(vec3 origin, vec3 direction, inout float seed)
{
	vec3 color = vec3(0.0);
	RayHit hit;
	for (int r = 0; r < RaysPerPixel; r++)
	{
		Ray ray = Ray(origin, direction, vec3(1.0));
		for (int stp = 0; stp < BounceTests + 1; stp++)
		{
			if (!TestHit(ray, hit))
			{
				ray.color *= GetSkyColorForDirection(ray.direction);
				break;
			}
			else
			{
				ray.color *= hit.color * dot(-hit.normal, ray.direction); // Lambert's cosine law
				// ray.direction = mix(GetFibDir(r, RaysPerPixel, hit.normal, Random(seed)), reflect(ray.direction, hit.normal), hit.specular);
				ray.direction = mix(GetRandDir(hit.normal, seed), reflect(ray.direction, hit.normal), hit.specular);
				ray.origin = hit.location;
				// ray.color = GetRandDir(hit.normal, seed);
				// break;
				// ray.color *= hit.normal; // Lambert's cosine law
			}
		}
		color += ray.color;
	}

	return color / RaysPerPixel;
}



// The code we want to execute in each invocation
void main() 
{
	ivec2 image_size = imageSize(m_renderedImage);
	// Coords in the range [-1,1]
	vec2 uv = vec2((gl_GlobalInvocationID.xy) / vec2(image_size) * 2.0 - 1.0);
	float aspect_ratio = float(image_size.x) / float(image_size.y);
	uv.y = - uv.y;

	vec3 direction = (inverse(m_cameraBuffer.projection) * vec4(uv, 0.0, 1.0)).xyz;
	direction = (m_cameraBuffer.transform * vec4(direction, 0.0)).xyz;
	direction = normalize(direction);

	//uint seed = uint(m_dataBuffer.time * gl_GlobalInvocationID.x * image_size.x + gl_GlobalInvocationID.y);
	float seed = fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 4358.5453123 * m_dataBuffer.time);
	vec3 outColor = CastRay(m_cameraBuffer.transform[3].xyz, direction, seed);

	// vec3 outColor = vec3(Random(seed), Random(seed), Random(seed));
	

	// gl_GlobalInvocationID.x uniquely identifies this invocation across all work groups
	// my_data_buffer.data[gl_GlobalInvocationID.x] *= 2.0;
	// imageStore(m_renderedImage, ivec2(gl_GlobalInvocationID.xy), vec4(uv.x, uv.y, 0.0f, 1.0f));
	imageStore(m_renderedImage, ivec2(gl_GlobalInvocationID.xy), vec4(outColor, 1.0));
}
