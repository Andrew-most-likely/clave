#version 440
// Samples the window snapshot and cuts Hyprland's rounded corners into it (the
// captured buffer itself is square).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float radius;
    vec4 winRect;
    vec4 iconRect;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 size = winRect.zw;
    vec2 p = qt_TexCoord0 * size;
    vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
    float d = length(max(q, 0.0)) - radius;
    float inside = 1.0 - smoothstep(-0.5, 0.5, d);
    fragColor = texture(source, qt_TexCoord0) * inside * qt_Opacity;
}
