using UnityEngine;

namespace Slock
{
    /// <summary>Runtime-generated textures and materials, so the game needs no authored assets yet.</summary>
    public static class Visuals
    {
        public static Material FloorTop, WallTop, WallSide, SlockBody, SlockJelly, SlockCore, WormJelly, WormCore, WormScared, WormFlash, Pickup, Pellet, GoldPellet, Clock, Key, Boost, Checkpoint, Gate;

        public static void Init()
        {
            if (FloorTop != null) return;

            // Tile art (Assets/Textures/Tiles, materials made by SlockBuild.EnsureAssets); generated grids as a fallback.
            FloorTop = Resources.Load<Material>("Slock/Tiles/Floor")
                       ?? Make(Grid(new Color(0.80f, 0.80f, 0.82f), new Color(0.32f, 0.32f, 0.36f), true), Color.white, 0.2f);
            WallTop = Resources.Load<Material>("Slock/Tiles/Tops") ?? FloorTop;
            WallSide = Resources.Load<Material>("Slock/Tiles/Walls")
                       ?? Make(Grid(new Color(0.10f, 0.62f, 0.92f), new Color(0.02f, 0.10f, 0.28f), false), Color.white, 0.35f);
            SlockBody = Make(null, new Color(0.95f, 0.10f, 0.16f), 0.85f, new Color(0.55f, 0.02f, 0.05f));
            SlockJelly = MakeJelly(new Color(0.85f, 0.0f, 0.06f, 0.72f), new Color(0.45f, 0.0f, 0.03f));
            SlockCore = Make(null, new Color(0.45f, 0.0f, 0.04f), 0.6f, new Color(0.5f, 0.0f, 0.05f));
            WormJelly = MakeJelly(new Color(0.15f, 0.85f, 0.1f, 0.62f), new Color(0.02f, 0.3f, 0.0f));
            WormCore = Make(null, new Color(0.02f, 0.3f, 0.02f), 0.6f, new Color(0.0f, 0.25f, 0.02f));
            WormScared = MakeJelly(new Color(0.15f, 0.3f, 1f, 0.62f), new Color(0.02f, 0.08f, 0.7f));
            WormFlash = MakeJelly(new Color(1f, 1f, 1f, 0.55f), new Color(0.7f, 0.7f, 0.7f));
            // Glass cubes with black edge lines.
            Pellet = MakeGlass(new Color(0.25f, 0.55f, 1f), new Color(0.1f, 0.35f, 1.2f));
            GoldPellet = MakeGlass(new Color(1f, 0.75f, 0.1f), new Color(1.3f, 0.8f, 0.1f));
            Clock = MakeGlass(new Color(0.3f, 0.9f, 1f), new Color(0.3f, 1.3f, 1.6f));
            Key = MakeGlass(new Color(1f, 0.3f, 1f), new Color(1.5f, 0.2f, 1.5f));
            Boost = Make(null, new Color(1f, 0.6f, 0.1f), 0.5f, new Color(2f, 0.9f, 0.1f));
            Gate = MakeGlass(new Color(0.1f, 0.8f, 0.8f), new Color(0.05f, 0.7f, 0.7f));
            Pickup = MakeGlass(new Color(1f, 0.85f, 0.15f), new Color(1.2f, 0.85f, 0.1f));
            Checkpoint = Make(null, new Color(0.2f, 1f, 0.95f), 0.5f, new Color(0.2f, 1.6f, 1.5f));
        }

        /// <summary>
        /// A see-through glass cube with solid black lines along every edge: an outline texture (black border,
        /// faint see-through middle) on each face, drawn double-sided so the back edges show through too.
        /// The same texture masks the glow, so the lines stay black.
        /// </summary>
        static Material MakeGlass(Color color, Color emission)
        {
            color.a = 1f;                                   // translucency comes from the texture
            // Template (SlockBuild.EnsureAssets) keeps the transparent + metallic-map variant in builds.
            var template = Resources.Load<Material>("Slock/SlockLitGlass");
            var m = template != null ? new Material(template) : MakeJelly(color, emission);
            ConfigureTransparent(m);
            m.SetColor("_BaseColor", color);
            var edges = EdgeTexture();
            m.mainTexture = edges;
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", emission);
            m.SetTexture("_EmissionMap", edges);            // lines don't glow
            // Lines are black non-reflective "metal" (a metal's shine takes its own colour: black), glass is glossy.
            m.SetTexture("_MetallicGlossMap", EdgeMask());
            m.SetFloat("_Smoothness", 1f);
            m.EnableKeyword("_METALLICSPECGLOSSMAP");
            m.SetFloat("_Cull", 0f);                        // both sides: back edges visible through the glass
            return m;
        }

        const int EdgeTexSize = 128, EdgeLine = 16;
        static bool IsEdge(int x, int y) => x < EdgeLine || y < EdgeLine || x >= EdgeTexSize - EdgeLine || y >= EdgeTexSize - EdgeLine;

        static Texture2D edgeTexture, edgeMask;

        /// <summary>Colour + alpha: black opaque border, see-through white middle (saved copy in Resources for builds).</summary>
        static Texture2D EdgeTexture() =>
            edgeTexture ??= Resources.Load<Texture2D>("Slock/GlassEdges") ?? BuildEdgeTexture();

        /// <summary>Freshly generated (readable) edge texture; the editor saves it to Resources/Slock/GlassEdges.png.</summary>
        public static Texture2D BuildEdgeTexture() =>
            FillTexture((x, y) => IsEdge(x, y) ? Color.black : new Color(1f, 1f, 1f, 0.72f), true);

        /// <summary>Metallic map (R = metallic, A = smoothness): border matte black metal, middle glossy glass.</summary>
        static Texture2D EdgeMask() =>
            edgeMask ??= Resources.Load<Texture2D>("Slock/GlassMask") ?? BuildEdgeMask();

        /// <summary>Freshly generated (readable) metallic mask; the editor saves it to Resources/Slock/GlassMask.png.</summary>
        public static Texture2D BuildEdgeMask() =>
            FillTexture((x, y) => IsEdge(x, y) ? new Color(1f, 1f, 1f, 0.2f) : new Color(0f, 0f, 0f, 0.92f), false);

        static Texture2D FillTexture(System.Func<int, int, Color> f, bool srgb)
        {
            var tex = new Texture2D(EdgeTexSize, EdgeTexSize, TextureFormat.RGBA32, true, !srgb)
                { wrapMode = TextureWrapMode.Clamp, anisoLevel = 4 };
            var px = new Color[EdgeTexSize * EdgeTexSize];
            for (int y = 0; y < EdgeTexSize; y++)
            for (int x = 0; x < EdgeTexSize; x++)
                px[y * EdgeTexSize + x] = f(x, y);
            tex.SetPixels(px);
            tex.Apply(true);
            return tex;
        }

        /// <summary>See-through, glossy jelly: alpha-blended URP Lit.</summary>
        static Material MakeJelly(Color color, Color emission)
        {
            // A saved template (made by SlockBuild.EnsureAssets) keeps the transparent shader variants in builds.
            var template = Resources.Load<Material>("Slock/SlockLitJelly");
            var m = template != null ? new Material(template) : Make(null, color, 0.95f, emission);
            ConfigureTransparent(m);
            m.SetColor("_BaseColor", color);
            m.SetFloat("_Smoothness", 0.95f);
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", emission);
            return m;
        }

        /// <summary>Switch a URP Lit material to alpha-blended transparency (what the inspector's "Surface Type" does).</summary>
        public static void ConfigureTransparent(Material m)
        {
            m.SetFloat("_Surface", 1f);
            m.SetFloat("_Blend", 0f);
            m.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
            m.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_SrcBlendAlpha", (float)UnityEngine.Rendering.BlendMode.One);
            m.SetFloat("_DstBlendAlpha", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_ZWrite", 0f);
            m.SetOverrideTag("RenderType", "Transparent");
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            m.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
        }

        static Material Make(Texture2D tex, Color color, float smoothness, Color? emission = null)
        {
            // Clone saved template materials (Assets/Resources/Slock) so builds keep the shader variants we use,
            // e.g. emission; a bare Shader.Find material can come out pink or unlit in a player build.
            var template = Resources.Load<Material>(emission.HasValue ? "Slock/SlockLitGlow" : "Slock/SlockLit");
            var m = template != null
                ? new Material(template)
                : new Material(Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard"));
            if (tex != null) m.mainTexture = tex;
            m.SetColor("_BaseColor", color);
            m.SetFloat("_Smoothness", smoothness);
            if (emission.HasValue)
            {
                m.EnableKeyword("_EMISSION");
                m.SetColor("_EmissionColor", emission.Value);
                m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
            }
            return m;
        }

        /// <summary>One tile of a grid: fill colour with dark edge lines (vertical-only when both == false).</summary>
        static Texture2D Grid(Color fill, Color line, bool both, int size = 128, int lineWidth = 4)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, true)
            {
                wrapMode = TextureWrapMode.Repeat,
                filterMode = FilterMode.Trilinear,
                anisoLevel = 8,
            };
            var px = new Color[size * size];
            int half = lineWidth / 2;
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                bool edgeX = x < half || x >= size - half;
                bool edgeY = both && (y < half || y >= size - half);
                // subtle vertical gradient so faces aren't perfectly flat
                float shade = 1f - 0.06f * (y / (float)size);
                px[y * size + x] = edgeX || edgeY ? line : fill * shade;
            }
            tex.SetPixels(px);
            tex.Apply(true);
            return tex;
        }
    }
}
