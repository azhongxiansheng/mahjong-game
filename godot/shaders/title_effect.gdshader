shader_type canvas_item;

uniform float glow_strength : hint_range(0.0, 5.0) = 3.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float wave_speed : hint_range(0.0, 10.0) = 1.5;
uniform float wave_amplitude : hint_range(0.0, 1.0) = 0.15;
uniform float brightness_threshold : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 过滤白色背景：检测亮度和饱和度
    float brightness = (tex_color.r + tex_color.g + tex_color.b) / 3.0;
    float saturation = max(max(tex_color.r, tex_color.g), tex_color.b) - min(min(tex_color.r, tex_color.g), tex_color.b);
    
    // 白色区域：高亮度+低饱和度
    float is_white = step(0.85, brightness) * step(saturation, 0.15);
    
    // 有色彩的亮区：金属文字部分
    float is_colored = step(brightness_threshold, brightness) * step(0.1, saturation);
    
    float alpha_mask = is_colored * (1.0 - is_white);
    
    // 波动光效
    float wave = sin(UV.x * 8.0 + TIME * wave_speed) * wave_amplitude;
    float pulse = sin(TIME * 1.8) * 0.5 + 0.5;
    
    // 增强金属质感
    vec3 enhanced = tex_color.rgb * (1.0 + wave * 0.3);
    
    // 边缘发光
    float edge_factor = pow(1.0 - alpha_mask, 2.0);
    vec3 glow = glow_color.rgb * edge_factor * glow_strength * (0.6 + pulse * 0.4) * alpha_mask;
    
    // 高光扫描
    float highlight_pos = fract(TIME * 0.3);
    float highlight = exp(-pow((UV.x - highlight_pos) * 5.0, 2.0)) * 0.5;
    
    vec3 final_color = enhanced + glow + vec3(1.0, 1.0, 0.9) * highlight * alpha_mask;
    
    COLOR = vec4(final_color, alpha_mask);
}
