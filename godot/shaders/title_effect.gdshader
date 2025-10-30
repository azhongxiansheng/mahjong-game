shader_type canvas_item;

uniform float glow_strength : hint_range(0.0, 5.0) = 2.5;
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float wave_speed : hint_range(0.0, 10.0) = 1.5;
uniform float wave_amplitude : hint_range(0.0, 1.0) = 0.15;
uniform float brightness_threshold : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 移除暗色背景（只保留明亮的文字部分）
    float brightness = (tex_color.r + tex_color.g + tex_color.b) / 3.0;
    float alpha_mask = smoothstep(brightness_threshold, brightness_threshold + 0.2, brightness);
    
    // 波动光效
    float wave = sin(UV.x * 8.0 + TIME * wave_speed) * wave_amplitude;
    float pulse = sin(TIME * 1.8) * 0.5 + 0.5;
    
    // 增强金属质感
    vec3 enhanced = tex_color.rgb * (1.0 + wave * 0.3);
    
    // 边缘发光（模拟图片中的橙色轮廓光）
    float edge_detect = 1.0 - alpha_mask;
    float edge_glow = pow(edge_detect, 1.5) * glow_strength * (0.6 + pulse * 0.4) * alpha_mask;
    vec3 glow = glow_color.rgb * edge_glow;
    
    // 高光扫描
    float highlight_pos = fract(TIME * 0.3);
    float highlight = exp(-pow((UV.x - highlight_pos) * 5.0, 2.0)) * 0.4;
    
    vec3 final_color = enhanced + glow + vec3(1.0, 1.0, 0.9) * highlight * alpha_mask;
    
    COLOR = vec4(final_color, alpha_mask);
}
