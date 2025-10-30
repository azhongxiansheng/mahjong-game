shader_type canvas_item;

uniform float glow_strength : hint_range(0.0, 5.0) = 2.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.0, 1.0);
uniform float wave_speed : hint_range(0.0, 10.0) = 2.0;
uniform float wave_amplitude : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    // 获取原始颜色
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 计算波动效果
    float wave = sin(UV.x * 10.0 + TIME * wave_speed) * wave_amplitude;
    float pulse = sin(TIME * 2.0) * 0.5 + 0.5;
    
    // 金属渐变
    float gradient = UV.x * 0.5 + UV.y * 0.5;
    vec3 metal_color = mix(
        vec3(1.0, 0.7, 0.2),  // 金黄色
        vec3(1.0, 0.9, 0.5),  // 亮金色
        gradient + wave
    );
    
    // 应用金属色
    vec3 final_color = tex_color.rgb * metal_color;
    
    // 添加发光边缘
    float edge = 1.0 - tex_color.a;
    float glow = pow(edge, 2.0) * glow_strength * pulse;
    final_color += glow_color.rgb * glow;
    
    // 高光
    float highlight = pow(sin(UV.x * 3.14159 + TIME), 8.0) * (0.3 + pulse * 0.2);
    final_color += vec3(1.0, 1.0, 0.8) * highlight;
    
    COLOR = vec4(final_color, tex_color.a);
}
