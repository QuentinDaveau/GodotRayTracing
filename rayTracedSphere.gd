@tool
extends CSGSphere3D
class_name RayTracedSphere

const RayTracedGroup = "RayTracedSpheres"

@export_group("Raytrace")
@export var _albedo: Color
@export var _emission: float
@export var _specular: float
@export var _clearcoat: float
@export var _subsurface_scattering: float



func _ready() -> void:
	if (!is_in_group(RayTracedGroup)):
		add_to_group(RayTracedGroup, true)


func GetFormattedData() -> PackedFloat32Array:
	# Center, Radius, then parameters defined above in same order
	# Needs to add padding for vec3
	var data: PackedFloat32Array = [
		transform.origin.x, transform.origin.y, transform.origin.z,
		radius,
		_albedo.r, _albedo.g, _albedo.b, _albedo.a,
		_emission,
		_specular,
		_clearcoat,
		_subsurface_scattering]
	return data
