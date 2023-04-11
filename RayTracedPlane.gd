@tool
extends CSGBox3D
class_name RayTracedPlane

const RayTracedGroup = "RayTracedPlanes"

@export_group("Raytrace")
@export var _albedo: Color
@export var _emission: float
@export var _roughness: float
@export var _clearcoat: float
@export var _subsurface_scattering: float



func _ready() -> void:
	if (!is_in_group(RayTracedGroup)):
		add_to_group(RayTracedGroup, true)


func _process(delta: float) -> void:
	size.y = 0.1


func GetFormattedData() -> PackedFloat32Array:
	# Center, normal, then parameters defined above in same order
	var data: PackedFloat32Array = [
		transform.origin.x, transform.origin.y, transform.origin.z, 0.0,
		transform.basis.y.x, transform.basis.y.y, transform.basis.y.z, 0.0,
		size.x, size.z, 0.0, 0.0,
		_albedo.r, _albedo.g, _albedo.b, _albedo.a,
		_emission,
		_roughness,
		_clearcoat,
		_subsurface_scattering]
	return data
