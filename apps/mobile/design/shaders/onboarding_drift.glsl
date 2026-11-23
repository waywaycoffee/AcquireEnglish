#version 100
precision highp float;

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Screenshot
 * @mipmap
 */
uniform sampler2D u_shot;

/**
 * @label Crop Y
 * @default 0
 * @range 0, 1
 */
uniform float u_cropY;

/**
 * @label Crop H
 * @default 1
 * @range 0.2, 1
 */
uniform float u_cropH;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  float z = 1.08 + sin(u_time * 0.45) * 0.025;
  vec2 c = vec2(0.5, 0.46);
  vec2 suv = (uv - c) / z + c;
  suv.x += sin(u_time * 0.32) * 0.012;
  suv.y = (1.0 - u_cropY - u_cropH) + suv.y * u_cropH;
  gl_FragColor = texture2D(u_shot, suv);
}
