#version 100
precision highp float;

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Color
 * @color
 * @default #22C55E
 */
uniform vec3 u_color;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy - vec2(0.5);
  uv.x *= u_resolution.x / max(u_resolution.y, 1.0);
  float d = length(uv);
  float beat = 0.5 + 0.5 * sin(u_time * 1.8);
  float radius = mix(0.28, 0.42, beat);
  float ring = smoothstep(radius, radius - 0.015, d) * smoothstep(radius - 0.07, radius - 0.03, d);
  float core = exp(-d * d * 16.0) * (0.28 + beat * 0.22);
  float alpha = clamp(ring * 0.9 + core, 0.0, 0.85);
  gl_FragColor = vec4(u_color, 1.0) * alpha;
}
