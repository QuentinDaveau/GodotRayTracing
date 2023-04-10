extends TextureRect

@onready var texture_size = get_viewport().get_visible_rect().size

func _ready() -> void:
	var image = Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGBAF)
	var image_texture = ImageTexture.create_from_image(image)
	texture = image_texture

func set_data(data : PackedByteArray):
	var image := Image.create_from_data(texture_size.x, texture_size.y, false, Image.FORMAT_RGBAF, data)
	texture.update(image)
