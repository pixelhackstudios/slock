using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

/// <summary>
/// One-click / command-line builds. From a terminal (with the editor closed):
///   Unity -batchmode -quit -projectPath . -executeMethod SlockBuild.Linux   (or .Windows, .Mac, .Web, .All)
///   Unity -batchmode -quit -projectPath . -executeMethod SlockBuild.EnsureAssets
/// Or in the editor: menu Slock > Build Linux / Windows / Mac / Web / All. Output goes to Builds/&lt;platform&gt;/.
/// </summary>
public static class SlockBuild
{
    /// <summary>
    /// Saved template materials so player builds keep the shader variants the game uses at runtime
    /// (emission, transparency). Safe to run repeatedly.
    /// </summary>
    [MenuItem("Slock/Create Template Materials")]
    public static void EnsureAssets()
    {
        // The jelly meshes are deformed every frame by JellyWobble, so they must be readable at runtime.
        foreach (var path in new[] { "Assets/Resources/Slock/SlockJelly.fbx", "Assets/Resources/Slock/SlockJellyLow.fbx" })
            if (AssetImporter.GetAtPath(path) is ModelImporter mi && !mi.isReadable)
            {
                mi.isReadable = true;
                mi.SaveAndReimport();
            }

        // Template materials. Unity's material validation strips keywords whose inputs aren't set (glow needs the
        // emissive GI flag, the metallic-map keyword needs a texture), and builds only keep shader variants that
        // saved materials use -- so set every input for real, every time.
        const string res = "Assets/Resources/Slock/";
        var edges = SaveTexture(res + "GlassEdges.png", Slock.Visuals.BuildEdgeTexture(), true);
        var mask = SaveTexture(res + "GlassMask.png", Slock.Visuals.BuildEdgeMask(), false);

        Template(res + "SlockLitGlow.mat", m => Glow(m));
        Template(res + "SlockLitJelly.mat", m => { Slock.Visuals.ConfigureTransparent(m); Glow(m); });
        Template(res + "SlockLitGlass.mat", m =>
        {
            Slock.Visuals.ConfigureTransparent(m);
            Glow(m);
            m.SetTexture("_BaseMap", edges);
            m.SetTexture("_EmissionMap", edges);
            m.SetTexture("_MetallicGlossMap", mask);
            m.EnableKeyword("_METALLICSPECGLOSSMAP");
            m.SetFloat("_Cull", 0f);
        });
        AssetDatabase.SaveAssets();
    }

    static void Glow(Material m)
    {
        m.SetColor("_EmissionColor", Color.white);
        m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
        m.EnableKeyword("_EMISSION");
    }

    static void Template(string path, System.Action<Material> setup)
    {
        var m = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (m == null)
        {
            m = new Material(Shader.Find("Universal Render Pipeline/Lit")) { name = System.IO.Path.GetFileNameWithoutExtension(path) };
            AssetDatabase.CreateAsset(m, path);
        }
        setup(m);
        EditorUtility.SetDirty(m);
    }

    static Texture2D SaveTexture(string path, Texture2D tex, bool srgb)
    {
        System.IO.File.WriteAllBytes(path, tex.EncodeToPNG());
        AssetDatabase.ImportAsset(path);
        var ti = (TextureImporter)AssetImporter.GetAtPath(path);
        ti.sRGBTexture = srgb;
        ti.alphaIsTransparency = srgb;
        ti.wrapMode = TextureWrapMode.Clamp;
        ti.SaveAndReimport();
        return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }

    /// <summary>Import settings + URP Lit materials for the tile art in Assets/Textures/Tiles (floor, tops, walls).</summary>
    [MenuItem("Slock/Create Tile Materials")]
    public static void EnsureTileMaterials()
    {
        const string tex = "Assets/Textures/Tiles/", mats = "Assets/Resources/Slock/Tiles";
        if (!AssetDatabase.IsValidFolder(mats)) AssetDatabase.CreateFolder("Assets/Resources/Slock", "Tiles");
        var sets = new (string file, string mat, Color tint)[]
        {
            ("floor", "Floor", Color.white),   // no tint: the tile art as drawn
            ("tops",  "Tops",  Color.white),
            ("walls", "Walls", Color.white),
        };
        foreach (var (file, matName, tint) in sets)
        {
            if (AssetImporter.GetAtPath(tex + file + "_base.png") == null) continue;
            Configure(tex + file + "_base.png", TextureImporterType.Default, true);
            Configure(tex + file + "_normal.png", TextureImporterType.NormalMap, false);
            Configure(tex + file + "_metalsmooth.png", TextureImporterType.Default, false);
            Configure(tex + file + "_ao.png", TextureImporterType.Default, false);

            string path = $"{mats}/{matName}.mat";
            var m = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (m == null)
            {
                m = new Material(Shader.Find("Universal Render Pipeline/Lit"));
                AssetDatabase.CreateAsset(m, path);
            }
            m.SetTexture("_BaseMap", AssetDatabase.LoadAssetAtPath<Texture2D>(tex + file + "_base.png"));
            m.SetColor("_BaseColor", tint);
            m.SetTexture("_BumpMap", AssetDatabase.LoadAssetAtPath<Texture2D>(tex + file + "_normal.png"));
            m.SetFloat("_BumpScale", 1f);
            m.SetTexture("_MetallicGlossMap", AssetDatabase.LoadAssetAtPath<Texture2D>(tex + file + "_metalsmooth.png"));
            m.SetFloat("_Smoothness", 1f);   // scales the map's smoothness
            m.SetTexture("_OcclusionMap", AssetDatabase.LoadAssetAtPath<Texture2D>(tex + file + "_ao.png"));
            m.SetFloat("_OcclusionStrength", 1f);
            m.EnableKeyword("_NORMALMAP");
            m.EnableKeyword("_METALLICSPECGLOSSMAP");
            m.EnableKeyword("_OCCLUSIONMAP");
            EditorUtility.SetDirty(m);
        }
        AssetDatabase.SaveAssets();
    }

    static void Configure(string path, TextureImporterType type, bool srgb)
    {
        if (AssetImporter.GetAtPath(path) is not TextureImporter ti) return;
        if (ti.textureType == type && ti.sRGBTexture == srgb && ti.maxTextureSize == 1024) return;
        ti.textureType = type;
        ti.sRGBTexture = srgb;      // maps other than colour are data, not colour
        ti.maxTextureSize = 1024;
        ti.wrapMode = TextureWrapMode.Repeat;
        ti.anisoLevel = 8;
        ti.SaveAndReimport();
    }

    [MenuItem("Slock/Build Linux")]
    public static void Linux() => Finish(Build(BuildTarget.StandaloneLinux64, "Builds/Linux/Slock.x86_64"));

    [MenuItem("Slock/Build Windows")]
    public static void Windows() => Finish(Build(BuildTarget.StandaloneWindows64, "Builds/Windows/Slock.exe"));

    [MenuItem("Slock/Build Mac")]
    public static void Mac() => Finish(Build(BuildTarget.StandaloneOSX, "Builds/Mac/Slock.app"));

    /// <summary>Browser build, ready to drop into GitHub Pages: open Builds/Web/index.html from any static host.</summary>
    [MenuItem("Slock/Build Web")]
    public static void Web() => Finish(BuildWeb());

    [MenuItem("Slock/Build All")]
    public static void All()
    {
        bool ok = Build(BuildTarget.StandaloneLinux64, "Builds/Linux/Slock.x86_64");
        ok &= Build(BuildTarget.StandaloneWindows64, "Builds/Windows/Slock.exe");
        ok &= Build(BuildTarget.StandaloneOSX, "Builds/Mac/Slock.app");
        ok &= BuildWeb();
        Finish(ok);
    }

    static bool BuildWeb()
    {
        // GitHub Pages can't send the Content-Encoding headers a compressed Unity web build normally needs;
        // gzip + decompression fallback lets the page unpack the files itself, so any static host works.
        PlayerSettings.WebGL.compressionFormat = WebGLCompressionFormat.Gzip;
        PlayerSettings.WebGL.decompressionFallback = true;
        return Build(BuildTarget.WebGL, "Builds/Web");
    }

    static bool Build(BuildTarget target, string path)
    {
        if (!BuildPipeline.IsBuildTargetSupported(BuildPipeline.GetBuildTargetGroup(target), target))
        {
            Debug.LogError($"Slock {target} build: that platform's Build Support module isn't installed (Unity Hub > Installs > Add modules).");
            return false;
        }
        EnsureAssets();
        EnsureTileMaterials();
        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
        {
            scenes = new[] { "Assets/Scenes/SampleScene.unity" },
            locationPathName = path,
            target = target,
            options = BuildOptions.None,
        });
        Debug.Log($"Slock {target} build: {report.summary.result}, {report.summary.totalSize / (1024 * 1024)} MB -> {path}");
        return report.summary.result == BuildResult.Succeeded;
    }

    static void Finish(bool ok)
    {
        if (Application.isBatchMode) EditorApplication.Exit(ok ? 0 : 1);
    }
}
