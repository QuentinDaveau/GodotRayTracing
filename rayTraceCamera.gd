extends Camera3D

var rd: RenderingDevice
var global_time : float = 0.0
var uniform_set
var pipeline: RID
var shader: RID
var output_tex : RID

var bindings : Array
var spheres: Array[RayTracedSphere] = []
var planes: Array[RayTracedPlane] = []


var m_raytracing := true


@onready
var light := %DirectionalLight3D


func matrix_to_bytes(t : Projection):
	# Helper function
	# Encodes the values of a "global_transform" into bytes
	var bytes : PackedByteArray = PackedFloat32Array([
		t.x.x, t.x.y, t.x.z, t.x.w,
		t.y.x, t.y.y, t.y.z, t.y.w,
		t.z.x, t.z.y, t.z.z, t.z.w,
		t.w.x, t.w.y, t.w.z, t.w.w
	]).to_byte_array()
	return bytes




func _ready() -> void:
	# Get all spheres
	for sphere in get_tree().get_nodes_in_group("RayTracedSpheres"):
		spheres.append(sphere)
	for plane in get_tree().get_nodes_in_group("RayTracedPlanes"):
		planes.append(plane)
	
	# Create a local rendering device.
	rd = RenderingServer.create_local_rendering_device()
	# Load GLSL shader
	var shader_file := load("res://compute.comp.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	# Create shader and pipeline
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	
	
	# Creating constant parameters
	# Output Texture Buffer
	var viewport_size := get_viewport().get_visible_rect().size
	var fmt := RDTextureFormat.new()
	fmt.width = viewport_size.x
	fmt.height = viewport_size.y
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var view := RDTextureView.new()
	var output_image := Image.create(viewport_size.x, viewport_size.y, false, Image.FORMAT_RGBAF)
	output_tex = rd.texture_create(fmt, view, [output_image.get_data()])
	var output_tex_uniform := RDUniform.new()
	output_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_tex_uniform.binding = 0
	output_tex_uniform.add_id(output_tex)
	
	# Bindings: Texture, time, camera, light, spheres, planes
	bindings.resize(6)
	bindings[0] = output_tex_uniform
	


func _process(delta: float) -> void:
	if (Input.is_action_pressed("RClick") && Input.get_last_mouse_velocity().length_squared() > 0.0):
		transform = transform.rotated(Vector3.UP, -Input.get_last_mouse_velocity().x * delta * 0.05)
		transform = transform.rotated(Vector3.UP.cross(transform.basis.z).normalized(), -Input.get_last_mouse_velocity().y * delta * 0.05)
	
	if (Input.is_action_just_pressed("ui_text_backspace")):
		m_raytracing = !m_raytracing
		if (!m_raytracing):
			%TextureRect.reset()
	
	if (m_raytracing):
		_render(delta)
	


func _render(delta: float) -> void:
	# Prepare data
#	var input := PackedFloat32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
#	var input_bytes := input.to_byte_array()
#	var buffer := rd.storage_buffer_create(input_bytes.size(), input_bytes)
#
#	# Create a uniform to assign the buffer to the rendering device
#	var uniform := RDUniform.new()
#	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
#	uniform.binding = 0 # this needs to match the "binding" in our shader file
#	uniform.add_id(buffer)
#	var uniform_set := rd.uniform_set_create([uniform], shader, 0) # the last parameter (the 0) needs to match the "set" in our shader file
	
	# Update time
	global_time += delta
	var params : PackedByteArray = PackedFloat32Array([global_time]).to_byte_array()
	var params_buffer = rd.storage_buffer_create(params.size(), params)
	var params_uniform := RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 1
	params_uniform.add_id(params_buffer)
	bindings[1] = params_uniform
	
	# Camera Matrices Buffer
	var camera_matrices_bytes := PackedByteArray()
	camera_matrices_bytes.append_array(matrix_to_bytes(Projection(global_transform))) # transform
	var aspect := get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y
	camera_matrices_bytes.append_array(matrix_to_bytes(Projection.create_perspective(fov, aspect, near, far))) # projection
	var camera_matrices_buffer = rd.storage_buffer_create(camera_matrices_bytes.size(), camera_matrices_bytes)
	var camera_matrices_uniform := RDUniform.new()
	camera_matrices_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	camera_matrices_uniform.binding = 2
	camera_matrices_uniform.add_id(camera_matrices_buffer)
	bindings[2] = camera_matrices_uniform
	
	# Directional Light Buffer
	var light_direction : Vector3 = -light.global_transform.basis.z.normalized()
	var light_data_bytes := PackedFloat32Array([
		light_direction.x, light_direction.y, light_direction.z,
		light.light_energy
	]).to_byte_array()
	var light_data_buffer = rd.storage_buffer_create(light_data_bytes.size(), light_data_bytes)
	var light_data_uniform := RDUniform.new()
	light_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	light_data_uniform.binding = 3
	light_data_uniform.add_id(light_data_buffer)
	bindings[3] = light_data_uniform
	
	# Spheres buffer
	var spheres_data := PackedFloat32Array([])
	for sphere in spheres:
		spheres_data += sphere.GetFormattedData()
	var spheres_data_bytes := spheres_data.to_byte_array()
	var spheres_data_buffer = rd.storage_buffer_create(spheres_data_bytes.size(), spheres_data_bytes)
	var spheres_data_uniform := RDUniform.new()
	spheres_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	spheres_data_uniform.binding = 4
	spheres_data_uniform.add_id(spheres_data_buffer)
	bindings[4] = spheres_data_uniform
	
	# Planes buffer
	var planes_data := PackedFloat32Array([])
	for plane in planes:
		planes_data += plane.GetFormattedData()
	var planes_data_bytes := planes_data.to_byte_array()
	var planes_data_buffer = rd.storage_buffer_create(planes_data_bytes.size(), planes_data_bytes)
	var planes_data_uniform := RDUniform.new()
	planes_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	planes_data_uniform.binding = 5
	planes_data_uniform.add_id(planes_data_buffer)
	bindings[5] = planes_data_uniform
	
	uniform_set = rd.uniform_set_create(bindings, shader, 0)
	
	# Processing the shader
	# Start compute list to start recording our compute commands
	var compute_list = rd.compute_list_begin()
	# Bind the pipeline, this tells the GPU what shader to use
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	# Binds the uniform set with the data we want to give our shader
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	# Dispatch (X,Y,Z) work groups
	var viewport_size := get_viewport().get_visible_rect().size
	rd.compute_list_dispatch(compute_list, viewport_size.x / 8, viewport_size.y / 8, 1)
	
	# Tell the GPU we are done with this compute task
	rd.compute_list_end()
	# Force the GPU to start our commands
	rd.submit()
	# Force the CPU to wait for the GPU to finish with the recorded commands
	rd.sync()
	
	# Now we can grab our data from the output texture
	var byte_data : PackedByteArray = rd.texture_get_data(output_tex, 0)
	%TextureRect.set_data(byte_data)
	
