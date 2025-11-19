shader_type canvas_item;

// Palette swap shader for Mana Seed character system
// Supports 3-color, 4-color, 5-color (hair), and skin ramps

// Uniform to control which ramp type this sprite uses
uniform int ramp_type = 0; // 0=3-color, 1=4-color, 2=hair(5-color), 3=skin

// Base color ramps (what's in the sprite)
// 3-color base ramp (00a)
uniform vec4 base_3color_1 : source_color = vec4(0.157, 0.157, 0.157, 1.0); // Dark
uniform vec4 base_3color_2 : source_color = vec4(0.376, 0.376, 0.376, 1.0); // Mid
uniform vec4 base_3color_3 : source_color = vec4(0.663, 0.663, 0.663, 1.0); // Light

// 4-color base ramp (00b)
uniform vec4 base_4color_1 : source_color = vec4(0.157, 0.157, 0.157, 1.0); // Darkest
uniform vec4 base_4color_2 : source_color = vec4(0.290, 0.290, 0.290, 1.0); // Dark
uniform vec4 base_4color_3 : source_color = vec4(0.475, 0.475, 0.475, 1.0); // Mid
uniform vec4 base_4color_4 : source_color = vec4(0.663, 0.663, 0.663, 1.0); // Light

// Hair base ramp (5-color)
uniform vec4 base_hair_1 : source_color = vec4(0.122, 0.082, 0.078, 1.0); // Darkest
uniform vec4 base_hair_2 : source_color = vec4(0.267, 0.180, 0.157, 1.0); // Dark
uniform vec4 base_hair_3 : source_color = vec4(0.475, 0.325, 0.282, 1.0); // Mid
uniform vec4 base_hair_4 : source_color = vec4(0.690, 0.514, 0.451, 1.0); // Light
uniform vec4 base_hair_5 : source_color = vec4(0.906, 0.753, 0.702, 1.0); // Lightest

// Skin base ramp
uniform vec4 base_skin_1 : source_color = vec4(0.361, 0.251, 0.196, 1.0); // Darkest
uniform vec4 base_skin_2 : source_color = vec4(0.573, 0.412, 0.325, 1.0); // Dark
uniform vec4 base_skin_3 : source_color = vec4(0.780, 0.608, 0.502, 1.0); // Mid
uniform vec4 base_skin_4 : source_color = vec4(0.949, 0.839, 0.737, 1.0); // Light

// Target color ramps (what we want to replace with)
// 3-color target
uniform vec4 target_3color_1 : source_color = vec4(0.157, 0.157, 0.157, 1.0);
uniform vec4 target_3color_2 : source_color = vec4(0.376, 0.376, 0.376, 1.0);
uniform vec4 target_3color_3 : source_color = vec4(0.663, 0.663, 0.663, 1.0);

// 4-color target
uniform vec4 target_4color_1 : source_color = vec4(0.157, 0.157, 0.157, 1.0);
uniform vec4 target_4color_2 : source_color = vec4(0.290, 0.290, 0.290, 1.0);
uniform vec4 target_4color_3 : source_color = vec4(0.475, 0.475, 0.475, 1.0);
uniform vec4 target_4color_4 : source_color = vec4(0.663, 0.663, 0.663, 1.0);

// Hair target (5-color)
uniform vec4 target_hair_1 : source_color = vec4(0.122, 0.082, 0.078, 1.0);
uniform vec4 target_hair_2 : source_color = vec4(0.267, 0.180, 0.157, 1.0);
uniform vec4 target_hair_3 : source_color = vec4(0.475, 0.325, 0.282, 1.0);
uniform vec4 target_hair_4 : source_color = vec4(0.690, 0.514, 0.451, 1.0);
uniform vec4 target_hair_5 : source_color = vec4(0.906, 0.753, 0.702, 1.0);

// Skin target
uniform vec4 target_skin_1 : source_color = vec4(0.361, 0.251, 0.196, 1.0);
uniform vec4 target_skin_2 : source_color = vec4(0.573, 0.412, 0.325, 1.0);
uniform vec4 target_skin_3 : source_color = vec4(0.780, 0.608, 0.502, 1.0);
uniform vec4 target_skin_4 : source_color = vec4(0.949, 0.839, 0.737, 1.0);

// Color comparison tolerance
const float TOLERANCE = 0.01;

bool colors_match(vec4 a, vec4 b) {
	return distance(a.rgb, b.rgb) < TOLERANCE;
}

void fragment() {
	vec4 pixel_color = texture(TEXTURE, UV);
	vec4 final_color = pixel_color;

	// Only process non-transparent pixels
	if (pixel_color.a > 0.0) {
		// 3-color ramp
		if (ramp_type == 0) {
			if (colors_match(pixel_color, base_3color_1)) {
				final_color = vec4(target_3color_1.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_3color_2)) {
				final_color = vec4(target_3color_2.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_3color_3)) {
				final_color = vec4(target_3color_3.rgb, pixel_color.a);
			}
		}
		// 4-color ramp
		else if (ramp_type == 1) {
			if (colors_match(pixel_color, base_4color_1)) {
				final_color = vec4(target_4color_1.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_4color_2)) {
				final_color = vec4(target_4color_2.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_4color_3)) {
				final_color = vec4(target_4color_3.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_4color_4)) {
				final_color = vec4(target_4color_4.rgb, pixel_color.a);
			}
		}
		// Hair ramp (5-color)
		else if (ramp_type == 2) {
			if (colors_match(pixel_color, base_hair_1)) {
				final_color = vec4(target_hair_1.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_hair_2)) {
				final_color = vec4(target_hair_2.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_hair_3)) {
				final_color = vec4(target_hair_3.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_hair_4)) {
				final_color = vec4(target_hair_4.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_hair_5)) {
				final_color = vec4(target_hair_5.rgb, pixel_color.a);
			}
		}
		// Skin ramp
		else if (ramp_type == 3) {
			if (colors_match(pixel_color, base_skin_1)) {
				final_color = vec4(target_skin_1.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_skin_2)) {
				final_color = vec4(target_skin_2.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_skin_3)) {
				final_color = vec4(target_skin_3.rgb, pixel_color.a);
			} else if (colors_match(pixel_color, base_skin_4)) {
				final_color = vec4(target_skin_4.rgb, pixel_color.a);
			}
		}
	}

	COLOR = final_color;
}
