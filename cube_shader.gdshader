shader_type spatial;
render_mode cull_back;

uniform sampler2D front_texture : source_color, filter_linear_mipmap;
uniform vec4 front_face_bg : source_color = vec4(0.95, 0.95, 0.98, 1.0);

// Webcam uniforms
uniform sampler2D webcam_texture : filter_linear_mipmap;
uniform sampler2D webcam_cbcr_texture : filter_linear_mipmap;
uniform int webcam_mode = 0; // 0: None, 1: RGB, 2: YCbCr 4:2:0 Bi-Planar
uniform int webcam_fit_mode = 0; // 0: Fit (letterbox full frame), 1: Cover (crop), 2: Stretch
uniform float webcam_aspect = 1.777778; // 16:9 default
uniform bool webcam_flip_h = true;
uniform vec4 webcam_face_bg : source_color = vec4(0.06, 0.08, 0.12, 1.0);

uniform vec4 cube_color : source_color = vec4(0.12, 0.15, 0.22, 1.0);
uniform vec4 border_color : source_color = vec4(0.35, 0.65, 0.95, 1.0);
uniform float border_thickness : hint_range(0.0, 0.1) = 0.035;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float metallic : hint_range(0.0, 1.0) = 0.15;
uniform vec3 cube_size = vec3(1.8, 1.8, 1.8);

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

// Convert YCbCr (macOS AVFoundation bi-planar) to standard RGB
vec3 ycbcr_to_rgb(float y, vec2 cbcr) {
	float u = cbcr.x - 0.5;
	float v = cbcr.y - 0.5;
	// ITU-R BT.709 / BT.601 conversion matrix
	float r = y + 1.402 * v;
	float g = y - 0.344136 * u - 0.714136 * v;
	float b = y + 1.772 * u;
	return clamp(vec3(r, g, b), vec3(0.0), vec3(1.0));
}

void fragment() {
	// Derive face normal from local position on the box (avoids a second varying).
	vec3 local_norm = v_local_pos / (cube_size * 0.5);
	vec3 abs_norm = abs(local_norm);
	vec2 face_uv = vec2(0.5);

	// Determine face: 0: Front (+Z), 1: Right (+X), 2: Back (-Z), 3: Left (-X), 4: Top (+Y), 5: Bottom (-Y)
	int face_id = 0;

	if (abs_norm.z >= abs_norm.x && abs_norm.z >= abs_norm.y) {
		if (local_norm.z > 0.0) {
			// Front (+Z)
			face_id = 0;
			face_uv = vec2(v_local_pos.x / cube_size.x + 0.5, 0.5 - v_local_pos.y / cube_size.y);
		} else {
			// Back (-Z)
			face_id = 2;
			face_uv = vec2(0.5 - v_local_pos.x / cube_size.x, 0.5 - v_local_pos.y / cube_size.y);
		}
	} else if (abs_norm.x >= abs_norm.y && abs_norm.x >= abs_norm.z) {
		if (local_norm.x > 0.0) {
			// Right (+X)
			face_id = 1;
			face_uv = vec2(0.5 - v_local_pos.z / cube_size.z, 0.5 - v_local_pos.y / cube_size.y);
		} else {
			// Left (-X)
			face_id = 3;
			face_uv = vec2(v_local_pos.z / cube_size.z + 0.5, 0.5 - v_local_pos.y / cube_size.y);
		}
	} else {
		if (local_norm.y > 0.0) {
			// Top (+Y)
			face_id = 4;
			face_uv = vec2(v_local_pos.x / cube_size.x + 0.5, 0.5 - v_local_pos.z / cube_size.z);
		} else {
			// Bottom (-Y)
			face_id = 5;
			face_uv = vec2(v_local_pos.x / cube_size.x + 0.5, v_local_pos.z / cube_size.z + 0.5);
		}
	}

	face_uv = clamp(face_uv, vec2(0.0), vec2(1.0));

	bool is_border = (face_uv.x < border_thickness || face_uv.x > (1.0 - border_thickness) ||
	                  face_uv.y < border_thickness || face_uv.y > (1.0 - border_thickness));

	vec3 base_color = cube_color.rgb;

	if (face_id == 0) {
		// Face 1: Image face (Front +Z)
		vec4 tex = texture(front_texture, face_uv);
		base_color = mix(front_face_bg.rgb, tex.rgb, tex.a);
	} else {
		// Faces 1 through 5: Live Webcam feed on all other 5 faces
		vec2 cam_uv = face_uv;
		bool in_bounds = true;

		if (webcam_fit_mode == 0) {
			// FIT (letterbox full frame)
			if (webcam_aspect >= 1.0) {
				cam_uv.y = (face_uv.y - 0.5) * webcam_aspect + 0.5;
				in_bounds = (cam_uv.y >= 0.0 && cam_uv.y <= 1.0);
			} else {
				cam_uv.x = (face_uv.x - 0.5) / webcam_aspect + 0.5;
				in_bounds = (cam_uv.x >= 0.0 && cam_uv.x <= 1.0);
			}
		} else if (webcam_fit_mode == 1) {
			// COVER (crop to fill)
			if (webcam_aspect >= 1.0) {
				cam_uv.x = (face_uv.x - 0.5) / webcam_aspect + 0.5;
			} else {
				cam_uv.y = (face_uv.y - 0.5) * webcam_aspect + 0.5;
			}
		}

		if (webcam_flip_h) {
			cam_uv.x = 1.0 - cam_uv.x;
		}

		if (in_bounds && webcam_mode == 2) {
			// YCbCr Bi-Planar mode (macOS Metal / iOS)
			float y_lum = texture(webcam_texture, cam_uv).r;
			vec2 cbcr = texture(webcam_cbcr_texture, cam_uv).rg;
			base_color = ycbcr_to_rgb(y_lum, cbcr);
		} else if (in_bounds && webcam_mode == 1) {
			// Standard RGB mode
			base_color = texture(webcam_texture, cam_uv).rgb;
		} else {
			// Letterbox / placeholder background
			base_color = webcam_face_bg.rgb;
		}
	}

	if (is_border) {
		base_color = mix(base_color, border_color.rgb, 0.9);
	}

	ALBEDO = base_color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
