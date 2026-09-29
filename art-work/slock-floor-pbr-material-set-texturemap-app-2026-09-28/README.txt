PBR material set generated from "slock-floor" with TextureMap.app
https://texturemap.app/pbr-map-generator

FILES
  *-normal-map-*.png              Tangent-space normal (OpenGL, +Y up)
  *-roughness-map-*.png           Roughness, not glossiness
  *-ambient-occlusion-map-*.png   Ambient occlusion
  *-height-map-16bit-*.png        Displacement / height, 16-bit grayscale
  *-metallic-map-*.png            Metalness

COLOR SPACE
  Every map here except the source image is DATA, not color. Import them
  as Non-Color (Blender) or with sRGB unticked (Unreal, Unity), or the
  engine will gamma-correct them and the material will read wrong.

BLENDER
  Roughness and Metallic -> Principled BSDF inputs of the same name.
  Normal -> Normal Map node -> Normal input.
  Height -> Displacement node -> Material Output Displacement.
  AO -> Mix (Multiply) against the ambient contribution, not base color.

UNREAL ENGINE
  Set the normal map texture to the Normalmap compression setting.
  Untick sRGB on roughness, AO, height and metallic.

UNITY
  The Lit shader wants SMOOTHNESS, which is 1 - roughness. Invert the
  roughness map on import or feed it through your shader smoothness
  source.

These maps are inferred from a single photograph, not measured. They are a
fast starting point — check them against reference before shipping.
