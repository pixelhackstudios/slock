// The game's look, ported from its Godot code (main.gd's lighting, section.gd's materials, jelly.gd and the
// shaders in scripts/): the same colours, light, reflections and outlines, so the site shows what the game shows.
import * as THREE from 'three'

/** A colour the way the game's code writes it: sRGB components, which may go past 1 for a glow. */
export const srgb = (r, g, b) => new THREE.Color().setRGB(r, g, b, THREE.SRGBColorSpace)

const DEG = Math.PI / 180

// ------------------------------------------------------------------ light (main.gd, _setup_lighting)

/** The sun, the grey fill and the grey sky the shiny things reflect. three.js lights are physical: Godot's
 *  energies are its values times pi. */
export function light(scene, renderer) {
  scene.background = new THREE.Color(0x000000)
  scene.add(new THREE.AmbientLight(srgb(0.36, 0.36, 0.36), Math.PI))

  const sun = new THREE.DirectionalLight(0xffffff, 1.3 * Math.PI)
  sun.userData.direction = new THREE.Vector3(0, 0, -1).applyEuler(new THREE.Euler(-58 * DEG, 35 * DEG, 0, 'YXZ'))
  sun.castShadow = true
  sun.shadow.intensity = 0.75
  sun.shadow.mapSize.set(2048, 2048)
  sun.shadow.bias = -0.0004
  sun.shadow.normalBias = 0.02
  sun.shadow.radius = 2
  scene.add(sun, sun.target)

  const pmrem = new THREE.PMREMGenerator(renderer)
  const sky = new THREE.Scene()
  sky.add(new THREE.Mesh(new THREE.SphereGeometry(1, 64, 32), skyMaterial()))
  scene.environment = pmrem.fromScene(sky, 0).texture
  pmrem.dispose()
  return sun
}

/** Aim the sun's shadow at `centre`, covering `size` units across. */
export function aimShadow(sun, centre, size) {
  const cam = sun.shadow.camera
  cam.left = cam.bottom = -size / 2
  cam.right = cam.top = size / 2
  cam.near = 0.5
  cam.far = size * 2 + 40
  cam.updateProjectionMatrix()
  sun.target.position.copy(centre)
  sun.position.copy(centre).addScaledVector(sun.userData.direction, -(size + 20))
}

// Godot's ProceduralSkyMaterial, as main.gd sets it up: grey, lighter overhead, darker below, no sun.
function skyMaterial() {
  return new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    uniforms: {
      top: { value: srgb(0.6, 0.6, 0.6) },
      horizon: { value: srgb(0.34, 0.34, 0.34) },
      groundHorizon: { value: srgb(0.26, 0.26, 0.26) },
      groundBottom: { value: srgb(0.1, 0.1, 0.1) },
    },
    vertexShader: /* glsl */ `
      varying vec3 vDir;
      void main() {
        vDir = position;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 top, horizon, groundHorizon, groundBottom;
      varying vec3 vDir;
      const float PI = 3.14159265;
      void main() {
        float angle = acos(clamp(normalize(vDir).y, -1.0, 1.0));
        float c = 1.0 - angle / (PI * 0.5);
        vec3 sky = mix(horizon, top, clamp(1.0 - pow(1.0 - c, 1.0 / 0.15), 0.0, 1.0));
        c = (angle - PI * 0.5) / (PI * 0.5);
        vec3 ground = mix(groundHorizon, groundBottom, clamp(1.0 - pow(1.0 - c, 1.0 / 0.02), 0.0, 1.0));
        gl_FragColor = vec4(angle < PI * 0.5 ? sky : ground, 1.0);
      }`,
  })
}

/** The game lights the shade with a flat grey and only reflects its sky; three.js would also light the shade from
 *  the sky. This takes that part out, for a material lit like the game's. */
export function reflectOnly(material) {
  const before = material.onBeforeCompile
  material.onBeforeCompile = (shader, renderer) => {
    before?.call(material, shader, renderer)
    shader.fragmentShader = shader.fragmentShader.replace('#include <lights_fragment_maps>',
      THREE.ShaderChunk.lights_fragment_maps.replace('iblIrradiance += getIBLIrradiance( geometryNormal );', ''))
  }
  return material
}

// ------------------------------------------------------------------ the maze (section.gd, _look)

/** The material for one of the maze kit's texture sets (textures/maze/<set>_*): albedo, normal map, and ORM
 *  (occlusion, roughness, metal), plus the pen's glow. */
export function mazeMaterial(maps) {
  const m = new THREE.MeshStandardMaterial({
    map: maps.albedo,
    normalMap: maps.normal,
    normalScale: new THREE.Vector2(1, -1), // glTF-style tangents, as GLTFLoader sets them up
    aoMap: maps.orm,
    roughnessMap: maps.orm,
    metalnessMap: maps.orm,
    roughness: 1,
    metalness: 1,
  })
  if (maps.emission) {
    m.emissiveMap = maps.emission
    m.emissive = new THREE.Color(0xffffff)
  }
  return reflectOnly(m)
}

// ------------------------------------------------------------------ jelly (jelly.gd, jelly.gdshader)

// jelly_wobble.gdshaderinc: the top sways behind the bottom, and the block squishes along an impact axis.
const WOBBLE = /* glsl */ `
  uniform vec2 sway;
  uniform float squish;
  uniform vec3 squishAxis;
  void wobble(inout vec3 vertex, inout vec3 normal) {
    vec3 n = squishAxis;
    float along = dot(vertex, n);
    vec3 p = n * (along * (1.0 - squish)) + (vertex - n * along) * (1.0 + squish * 0.5);
    float nAlong = dot(normal, n);
    vec3 nrm = n * (nAlong / (1.0 - squish)) + (normal - n * nAlong) / (1.0 + squish * 0.5);
    float h = clamp(p.y + 0.5, 0.0, 1.0);
    p.xz += sway * h * h;
    nrm.y -= dot(sway * 2.0 * h, nrm.xz);
    vertex = p;
    normal = normalize(nrm);
  }
`

export const JELLY = {
  slock: { color: srgb(0.85, 0.0, 0.06), alpha: 0.72, glow: srgb(0.45, 0.0, 0.03) },
  swurm: { color: srgb(0.2, 0.75, 0.12), alpha: 0.72, glow: srgb(0.02, 0.18, 0.0) },
  scared: { color: srgb(0.15, 0.3, 1.0), alpha: 0.72, glow: srgb(0.02, 0.08, 0.5) },
  flash: { color: srgb(1, 1, 1), alpha: 0.72, glow: srgb(0.6, 0.6, 0.6) },
}

/** See-through jelly, bent by the wobble. `wobble` holds its uniforms (sway, squish, squishAxis), shared with its
 *  outline. */
export function jellyMaterial(look, wobble) {
  const m = new THREE.MeshStandardMaterial({
    color: look.color.clone(),
    emissive: look.glow.clone(),
    roughness: 0.05,
    metalness: 0,
    transparent: true,
    opacity: look.alpha,
    depthWrite: false,
  })
  m.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, wobble)
    shader.vertexShader = WOBBLE + shader.vertexShader
      .replace('#include <beginnormal_vertex>', `#include <beginnormal_vertex>
        vec3 wobbled = position;
        wobble(wobbled, objectNormal);`)
      .replace('#include <begin_vertex>', 'vec3 transformed = wobbled;')
  }
  return reflectOnly(m)
}

/** The dark core inside Slock. */
export function coreMaterial() {
  return reflectOnly(new THREE.MeshStandardMaterial({
    color: srgb(0.45, 0.0, 0.04), roughness: 0.4, emissive: srgb(0.5, 0.0, 0.05),
  }))
}

// jelly_outline.gdshader: the block's back faces pushed out a fixed number of pixels, kept only where the line of
// sight misses the (wobbled, rounded) block itself.
export function jellyOutlineMaterial(wobble, frame) {
  return new THREE.ShaderMaterial({
    side: THREE.BackSide,
    transparent: true,
    depthWrite: false,
    uniforms: {
      ...wobble,
      viewToModel: { value: new THREE.Matrix4() },
      viewport: frame.viewport,
      inverseProjection: frame.inverseProjection,
      widthPx: frame.outlinePx,
    },
    vertexShader: WOBBLE + /* glsl */ `
      uniform vec2 viewport;
      uniform float widthPx;
      void main() {
        vec3 p = position;
        vec3 n = normal;
        wobble(p, n);
        vec4 clip = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
        vec3 viewNormal = normalize(normalMatrix * n);
        vec2 outDir = (projectionMatrix * vec4(viewNormal, 0.0)).xy;
        if (dot(outDir, outDir) > 1e-12) clip.xy += normalize(outDir) * widthPx * 2.0 / viewport * clip.w;
        gl_Position = clip;
      }`,
    fragmentShader: /* glsl */ `
      uniform vec2 sway;
      uniform float squish;
      uniform vec3 squishAxis;
      uniform mat4 viewToModel;
      uniform mat4 inverseProjection;
      uniform vec2 viewport;
      const float ROUNDING = 0.12;
      const float INSET = 0.006;
      float blockDistance(vec3 p) {
        float h = clamp(p.y + 0.5, 0.0, 1.0);
        p.xz -= sway * h * h;
        vec3 n = squishAxis;
        float along = dot(p, n);
        p = n * (along / (1.0 - squish)) + (p - n * along) / (1.0 + squish * 0.5);
        vec3 q = abs(p) - vec3(0.5 - ROUNDING);
        return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - (ROUNDING - INSET);
      }
      void main() {
        vec2 uv = gl_FragCoord.xy / viewport;
        vec4 farPoint = inverseProjection * vec4(uv * 2.0 - 1.0, 0.5, 1.0);
        vec3 origin = (viewToModel * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        vec3 dir = normalize((viewToModel * vec4(farPoint.xyz / farPoint.w, 0.0)).xyz);
        vec3 lo = (vec3(-0.9) - origin) / dir;
        vec3 hi = (vec3(0.9) - origin) / dir;
        float t = max(max(min(lo.x, hi.x), min(lo.y, hi.y)), min(lo.z, hi.z));
        float tEnd = min(min(max(lo.x, hi.x), max(lo.y, hi.y)), max(lo.z, hi.z));
        t = max(t, 0.0);
        for (int i = 0; i < 96; i++) {
          if (t >= tEnd) break;
          float d = blockDistance(origin + dir * t);
          if (d < 0.00002) discard;
          t += d * 0.7;
        }
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
      }`,
  })
}

// ------------------------------------------------------------------ pellets (orb.gdshader, outline.gdshader)

export const ORBS = {
  pellet: { radius: 0.115, height: 0.3, bob: 0.06, color: srgb(0.25, 0.55, 1.0), glow: srgb(0.1, 0.35, 1.2) },
  gold: { radius: 0.14, height: 0.3, bob: 0.06, color: srgb(1.0, 0.75, 0.1), glow: srgb(1.3, 0.8, 0.1) },
  power: { radius: 0.23, height: 0.6, bob: 0.12, color: srgb(1.0, 0.85, 0.15), glow: srgb(1.2, 0.85, 0.1) },
}

const BOB = /* glsl */ `
  uniform float time;
  attribute vec3 bob; // phase, speed (rad/s), height
`

/** See-through glowing orbs, drawn as one batch; each bobs at its own pace (the `bob` attribute). */
export function orbMaterial(look, clock) {
  const m = new THREE.MeshStandardMaterial({
    color: look.color, emissive: look.glow, roughness: 0.05, metalness: 0,
    transparent: true, opacity: 0.72, depthWrite: false,
  })
  m.onBeforeCompile = (shader) => {
    shader.uniforms.time = clock
    shader.vertexShader = BOB + shader.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
      transformed.y += sin((time + bob.x) * bob.y) * bob.z;`)
  }
  return reflectOnly(m)
}

/** The black ring round an orb: a camera-facing square with everything but a thin ring cut away. */
export function orbOutlineMaterial(radius, halfSize, clock, frame) {
  return new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    uniforms: { time: clock, radius: { value: radius }, halfSize: { value: halfSize }, widthPx: frame.orbOutlinePx },
    vertexShader: BOB + /* glsl */ `
      varying vec2 vUv;
      void main() {
        vec4 centre = instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0);
        centre.y += sin((time + bob.x) * bob.y) * bob.z;
        vec4 view = modelViewMatrix * centre;
        view.xy += position.xy;
        vUv = uv;
        gl_Position = projectionMatrix * view;
      }`,
    fragmentShader: /* glsl */ `
      uniform float radius, halfSize, widthPx;
      varying vec2 vUv;
      void main() {
        float d = length(vUv - 0.5) * 2.0 * halfSize;
        float px = fwidth(d);
        float inner = step(radius - 0.5 * px, d);
        float outer = 1.0 - smoothstep(radius + (widthPx - 0.5) * px, radius + (widthPx + 0.5) * px, d);
        float a = inner * outer;
        if (a <= 0.0) discard;
        gl_FragColor = vec4(0.0, 0.0, 0.0, a);
      }`,
  })
}

// ------------------------------------------------------------------ models (section.gd, _dress; model_outline.gdshader)

/** Give a model a black outline a fixed number of pixels wide: its materials mark their pixels in the stencil
 *  buffer, and its back faces, pushed out, draw only where nothing is marked (after everything else). */
export function outlineModel(root, frame) {
  const outline = modelOutlineMaterial(frame)
  const meshes = []
  root.traverse((o) => { if (o.isMesh) meshes.push(o) })
  for (const mesh of meshes) {
    for (const m of [mesh.material].flat()) {
      m.stencilWrite = true
      m.stencilRef = 1
      m.stencilFunc = THREE.AlwaysStencilFunc
      m.stencilZPass = THREE.ReplaceStencilOp
    }
    const shell = new THREE.Mesh(mesh.geometry, outline)
    shell.renderOrder = 10
    shell.castShadow = false
    mesh.add(shell)
  }
}

let sharedOutline = null
function modelOutlineMaterial(frame) {
  sharedOutline ??= new THREE.ShaderMaterial({
    side: THREE.BackSide,
    transparent: true,
    depthWrite: false,
    stencilWrite: true,
    stencilRef: 1,
    stencilFunc: THREE.NotEqualStencilFunc,
    uniforms: { viewport: frame.viewport, widthPx: frame.modelOutlinePx },
    vertexShader: /* glsl */ `
      uniform vec2 viewport;
      uniform float widthPx;
      void main() {
        vec4 clip = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        vec3 viewNormal = normalize(normalMatrix * normal);
        vec2 outDir = (projectionMatrix * vec4(viewNormal, 0.0)).xy;
        if (dot(outDir, outDir) > 1e-12) clip.xy += normalize(outDir) * widthPx * 2.0 / viewport * clip.w;
        gl_Position = clip;
      }`,
    fragmentShader: 'void main() { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); }',
  })
  return sharedOutline
}

// ------------------------------------------------------------------ the gate (gate_barrier.gdshader)

export function gateBarrierMaterial(clock) {
  return new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    uniforms: { time: clock, tint: { value: srgb(0.12, 0.95, 0.9) } },
    vertexShader: /* glsl */ `
      varying vec3 vModel;
      varying vec3 vNormal;
      varying vec3 vView;
      void main() {
        vModel = position;
        vec4 view = modelViewMatrix * vec4(position, 1.0);
        vNormal = normalize(normalMatrix * normal);
        vView = -view.xyz;
        gl_Position = projectionMatrix * view;
      }`,
    fragmentShader: /* glsl */ `
      uniform float time;
      uniform vec3 tint;
      varying vec3 vModel;
      varying vec3 vNormal;
      varying vec3 vView;
      const float TAU = 6.28318531;
      void main() {
        float edge = 1.0 - abs(dot(normalize(vNormal), normalize(vView)));
        edge *= edge;
        float band = pow(0.5 + 0.5 * sin((vModel.y * 7.0 - time * 0.35) * TAU), 6.0);
        vec2 cell = abs(fract(vec2(vModel.x + vModel.z, vModel.y) * 8.0) - 0.5);
        float grid = smoothstep(0.44, 0.5, max(cell.x, cell.y)) * 0.12;
        float fade = smoothstep(0.0, 0.08, vModel.y);
        vec3 colour = tint * (1.0 + band * 0.6 + edge * 0.8);
        float alpha = clamp((0.22 + edge * 0.55 + band * 0.18 + grid) * mix(0.6, 1.0, fade), 0.0, 0.95);
        gl_FragColor = vec4(colour, alpha);
        #include <colorspace_fragment>
      }`,
  })
}
