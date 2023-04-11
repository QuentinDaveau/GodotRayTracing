#[compute]
#version 450
#pragma vscode_glsllint_stage : comp

struct Sphere
{
	vec3 	center;
	float 	radius;
	vec4 	color;
	float 	emission;
	float 	roughness;
	float 	clearcoat;
	float 	subsurface_scattering;
};

struct Plane
{
	vec3 	location;
	vec3 	normal;
	vec2	scale;
	vec4 	color;
	float 	emission;
	float 	roughness;
	float 	clearcoat;
	float 	subsurface_scattering;
};

struct Ray 
{
	vec3 origin;
	vec3 direction;
	vec3 energy;
};

struct RayHit
{
	vec3 location;
	vec3 normal;
	float dist;
	vec4 color;
	// float specular;
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

vec4 SkyLow = vec4(0.6, 0.4, 0.2, 1.0);
vec4 SkyMiddle = vec4(0.35, 0.7, 0.8, 1.0);
vec4 SkyHigh = vec4(0.7, 0.8, 0.9, 1.0);
vec4 LightColor = vec4(1.0);

int BounceTests = 10;



void TestSphereHit(Ray ray, Sphere sphere, inout RayHit bestHit)
{
	// Calculate distance along the ray where the sphere is intersected
	float radSqr = sphere.radius * sphere.radius;
	vec3 direction = sphere.center - ray.origin;
	float proj = dot(ray.direction, direction);
	if (proj < 0)
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
		bestHit.color = sphere.color;
		// bestHit.specular = sphere.specular;
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
			bestHit.color = plane.color;
		}
	}
}



// Unpacking the sphere
Sphere GetSphere(mat4 sphereData)
{
	//vec3 	center;
	//float 	radius;
	//vec4 	color;
	//float 	emission;
	//float 	roughness;
	//float 	clearcoat;
	//float 	subsurface_scattering;
	Sphere sphere;
	sphere.center = sphereData[0].xyz;
	sphere.radius = sphereData[0].w;
	return sphere;
}


vec3 GetSkyColorForDirection(vec3 direction)
{
	float amount = dot(vec3(0.0, 1.0, 0.0), direction);
	float lightAmount = pow(max(dot(-direction, m_lightBuffer.direction), 0.0), 100.0);
	if (amount >= 0.0)
		return mix(mix(SkyMiddle, SkyHigh, amount * amount).xyz, LightColor.xyz, lightAmount);
	else
		return mix(SkyMiddle, SkyLow, amount * amount).xyz;
}



bool TestHit(inout Ray ray)
{
	RayHit bestHit;
	bestHit.dist = 99999999.0;
	bestHit.normal = vec3(0.0);

	// Testing spheres
	for (int i = 0; i < m_spheresBuffer.spheres.length(); i++)
	{
		TestSphereHit(ray, m_spheresBuffer.spheres[i], bestHit);
	}

	// Testing the planes
	for (int i = 0; i < m_planesBuffer.planes.length(); i++)
	{
		TestPlaneHit(ray, m_planesBuffer.planes[i], bestHit);
	}

	// We didn't hit anything, testing against the sky
	if (bestHit.normal == vec3(0.0))
	{
		ray.energy = GetSkyColorForDirection(ray.direction);
		return false;
	}
	else
	{
		ray.energy = bestHit.color.xyz;
		ray.direction = reflect(ray.direction, bestHit.normal);
		ray.origin = bestHit.location;
	}

	return true;
}



vec3 CastRay(vec3 origin, vec3 direction)
{
	Ray ray;
	ray.origin = origin;
	ray.direction = direction;
	ray.energy = vec3(0.0);

	for (int i = 0; i < BounceTests; i++)
	{
		if (!TestHit(ray))
			break;
	}
	return ray.energy;
}



// The code we want to execute in each invocation
void main() 
{
	ivec2 image_size = imageSize(m_renderedImage);
	// Coords in the range [-1,1]
	vec2 uv = vec2((gl_GlobalInvocationID.xy) / vec2(image_size) * 2.0 - 1.0);
	float aspect_ratio = float(image_size.x) / float(image_size.y);
	uv.y = - uv.y;
	// uv.x *= aspect_ratio;
	vec3 direction = (inverse(m_cameraBuffer.projection) * vec4(uv, 0.0, 1.0)).xyz;
	direction = (m_cameraBuffer.transform * vec4(direction, 0.0)).xyz;
	direction = normalize(direction);

	vec3 outColor = CastRay(m_cameraBuffer.transform[3].xyz, direction);
	

	// gl_GlobalInvocationID.x uniquely identifies this invocation across all work groups
	// my_data_buffer.data[gl_GlobalInvocationID.x] *= 2.0;
	// imageStore(m_renderedImage, ivec2(gl_GlobalInvocationID.xy), vec4(uv.x, uv.y, 0.0f, 1.0f));
	imageStore(m_renderedImage, ivec2(gl_GlobalInvocationID.xy), vec4(outColor, 1.0));
}
