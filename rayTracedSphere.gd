@tool
extends CSGSphere3D
class_name RayTracedSphere

const RayTracedGroup = "RayTracedObjects"

@export_group("Raytrace")
@export var _albedo: Color
@export var _emission: float
@export var _roughness: float
@export var _clearcoat: float
@export var _subsurface_scattering: float



func _ready() -> void:
	if (!is_in_group(RayTracedGroup)):
		add_to_group(RayTracedGroup, true)


func GetFormattedData() -> PackedByteArray:
	# Center, Radius, then parameters defined above in same order
	var data: PackedByteArray = [
		transform.origin.x, transform.origin.y, transform.origin.z,
		radius,
		_albedo.r, _albedo.g, _albedo.b, _albedo.a,
		_emission,
		_roughness,
		_clearcoat,
		_subsurface_scattering]
	return data
