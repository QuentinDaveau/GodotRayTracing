#[compute]
#version 450
#pragma vscode_glsllint_stage : comp

struct SphereData
{
	vec3 location;
	// vec4 rotation;
	float radius;
	vec4 color;
	float emission;
	float roughness;
	float clearcoat;
	float subsurface_scattering;
};

// Invocations in the (x, y, z) dimension
layout(local_size_x = 2, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D m_renderedImage;

layout(set = 0, binding = 1, std430) restrict buffer DataBuffer {
	float time;
}
m_dataBuffer;

layout(set = 0, binding = 2, std430) restrict buffer CameraBuffer {
	mat4 matrix;
}
m_cameraBuffer;


layout(set = 0, binding = 3, std430) restrict buffer LightBuffer {
	vec3 direction;
	float intensity;
}
m_lightBuffer;


layout(set = 0, binding = 4, std430) restrict buffer SpheresBuffer {
	float data[];
}
m_spheresBuffer;


// The code we want to execute in each invocation
void main() {
	// gl_GlobalInvocationID.x uniquely identifies this invocation across all work groups
	// my_data_buffer.data[gl_GlobalInvocationID.x] *= 2.0;
	imageStore(m_renderedImage, ivec2(gl_GlobalInvocationID.xy), vec4(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y, 0.0f, 1.0f));
}
