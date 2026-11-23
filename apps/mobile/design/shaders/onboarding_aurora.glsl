#version 100
precision highp float;

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Glow
 * @color
 * @default #22C55E
 */
uniform vec3 u_glow;

/**
 * @label Drift
 * @default 0.32
 * @range 0.05, 1.2
 */
uniform float u_speed;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  float t = u_time * u_speed;

  vec2 p = uv - vec2(0.52, 0.46);
  vec2 b1 = vec2(sin(t) * 0.32, cos(t * 0.72) * 0.16 - 0.06);
  vec2 b2 = vec2(cos(t * 0.55 + 1.4) * 0.26, sin(t * 0.83) * 0.2 + 0.12);
  vec2 b3 = vec2(sin(t * 0.4 + 2.1) * 0.18 - 0.2, cos(t * 0.63) * 0.1 + 0.22);

  float g1 = exp(-dot(p - b1, p - b1) * 7.5);
  float g2 = exp(-dot(p - b2, p - b2) * 11.0);
  float g3 = exp(-dot(p - b3, p - b3) * 14.0);

  vec3 base = vec3(0.027, 0.035, 0.051);
  vec3 ember = vec3(0.12, 0.45, 0.95);
  vec3 col = base;
  col += u_glow * (g1 * 0.42 + g3 * 0.16);
  col += ember * (g2 * 0.14);

  float sweep = sin((uv.x * 1.6 + uv.y * 0.4) * 6.283 + t * 1.6);
  col += u_glow * smoothstep(0.82, 1.0, sweep) * 0.05;

  float vig = smoothstep(1.05, 0.28, length((uv - vec2(0.5, 0.45)) * vec2(1.05, 1.2)));
  col *= mix(0.45, 1.0, vig);

  gl_FragColor = vec4(col, 1.0);
}
