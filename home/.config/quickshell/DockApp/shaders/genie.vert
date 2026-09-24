#version 440
// macOS genie: the window's rows slide down into the dock icon while its sides
// bend in toward the icon, bottom rows first. The mesh is a tall grid over the
// window texture; every vertex is placed from its texture coordinate alone,
// in the coordinates of the full-screen ShaderEffect.
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 = the window, 1 = inside the icon
    float radius;     // window corner radius, in window pixels
    vec4 winRect;     // x, y, width, height
    vec4 iconRect;
};

void main() {
    vec2 uv = qt_MultiTexCoord0;
    qt_TexCoord0 = uv;

    // The sides bend first, the slide into the icon overlaps and follows.
    float bend = smoothstep(0.0, 0.45, progress);
    float slide = smoothstep(0.1, 1.0, progress);

    // Bottom rows (uv.y = 1) start and finish their slide earlier.
    float rowT = clamp(slide * 1.6 - (1.0 - uv.y) * 0.6, 0.0, 1.0);
    float y = mix(winRect.y + uv.y * winRect.w, iconRect.y + uv.y * iconRect.w, rowT);

    // Funnel: full window width at the window's top edge, icon width from the
    // icon's top edge down.
    float span = max(iconRect.y - winRect.y, 1.0);
    float f = smoothstep(0.0, 1.0, clamp((y - winRect.y) / span, 0.0, 1.0)) * bend;
    f = max(f, rowT);
    float left = mix(winRect.x, iconRect.x, f);
    float right = mix(winRect.x + winRect.z, iconRect.x + iconRect.z, f);

    gl_Position = qt_Matrix * vec4(mix(left, right, uv.x), y, 0.0, 1.0);
}
