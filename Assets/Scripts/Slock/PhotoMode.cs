using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Slock
{
    /// <summary>
    /// Stages and captures promo screenshots, then quits. Run a build with:
    ///     Slock.x86_64 -slockshots /some/folder [-seed 7] -screen-fullscreen 0 -screen-width 1920 -screen-height 1080
    /// In the editor, add this component during Play and set <see cref="dir"/>.
    /// Shots with the HUD use the screen (2x supersampled); the rest are rendered clean at 4K.
    /// </summary>
    public class PhotoMode : MonoBehaviour
    {
        public string dir;
        public int seed = 7;
        public bool quitWhenDone = true;

        public static void StartIfRequested(GameManager gm)
        {
            var args = System.Environment.GetCommandLineArgs();
            int i = System.Array.IndexOf(args, "-slockshots");
            if (i < 0) return;
            var pm = gm.gameObject.AddComponent<PhotoMode>();
            pm.dir = i + 1 < args.Length ? args[i + 1] : Application.persistentDataPath;
            int s = System.Array.IndexOf(args, "-seed");
            if (s >= 0 && s + 1 < args.Length && int.TryParse(args[s + 1], out var seed)) pm.seed = seed;
        }

        IEnumerator Start()
        {
            Directory.CreateDirectory(dir);
            var gm = GameManager.I;
            var rig = FindAnyObjectByType<TiltCameraRig>();
            float yaw = rig.yaw * Mathf.Deg2Rad;
            var towardZ = new Vector2(-Mathf.Sin(yaw), Mathf.Cos(yaw)); // tilt that pushes the slock up the course (+z)

            // 1. Title screen (with the studio credit).
            yield return new WaitForSeconds(1.5f);
            yield return Hud("01_title.png");

            // 2. Gameplay: sliding into the maze, leaning with the tilt.
            Random.InitState(seed);
            gm.BeginRun();
            yield return new WaitForSeconds(0.6f);
            var s = FindAnyObjectByType<SlockController>();
            rig.overrideTilt = towardZ * 0.8f;
            yield return new WaitForSeconds(0.9f);
            yield return Hud("02_gameplay.png");

            // 3. Jelly close-up: slid up against the start wall.
            rig.overrideTilt = Vector2.zero;
            s.ResetTo(new Vector3(0f, s.Height * 0.5f + 0.02f, 5f));
            yield return new WaitForSeconds(0.6f);
            rig.overrideTilt = -towardZ;
            yield return new WaitForSeconds(1.2f);
            var p = s.transform.position;
            Render("03_jelly.png", p + new Vector3(2.3f, 1.5f, 1.6f), p + Vector3.up * 0.15f, 32f);
            rig.overrideTilt = Vector2.zero;

            // 4. Power mode: blue jelly worms.
            gm.ForcePower(30f);
            yield return new WaitForSeconds(1.2f);
            var worm = FindInSection<Worm>(0);
            if (worm != null)
            {
                var w = worm.transform.position;
                Render("04_power.png", w + new Vector3(-2.6f, 3.0f, -3.2f), w, 38f);
            }

            // 5. Side room off the maze's left edge: gold pellets, clock or key, boost ramp.
            foreach (var ramp in Section(0).GetComponentsInChildren<BoostRamp>())
            {
                if (ramp.up.x <= 0f) continue;
                var target = ramp.transform.position + new Vector3(-5.5f, -1.4f, 1.5f);
                Render("05_side_room.png", target + new Vector3(-3.5f, 7.5f, -8f), target, 42f);
                break;
            }

            // 6. Overview: the floating sections climbing away.
            gm.EnsureSections(1);
            yield return null;
            Render("06_overview.png", new Vector3(-24f, 15f, -16f), new Vector3(0f, 1.5f, 34f), 40f);

            // 7. A deep section: smaller blocks, denser maze.
            int k = 12;
            gm.EnsureSections(k);
            yield return null;
            var deep = Section(k);
            float ts = deep.TileSize;
            s.SetSizeImmediate(ts);
            s.SetGrid(ts, deep.Z0);
            s.ResetTo(deep.TileCenter(deep.Center, 1) + Vector3.up * (s.Height * 0.5f + 0.02f));
            rig.zoom = Mathf.Lerp(1f, ts, 0.5f);
            rig.SnapToTarget();
            rig.overrideTilt = towardZ * 0.3f;
            yield return new WaitForSeconds(1.5f);
            Render("07_deep.png", rig.transform.position, rig.transform.position + rig.transform.forward, Camera.main.fieldOfView);

            Debug.Log("[photomode] saved to " + dir);
            if (quitWhenDone)
            {
                yield return new WaitForSeconds(0.5f);
                Application.Quit();
            }
        }

        string PathOf(string file) => System.IO.Path.Combine(dir, file);

        IEnumerator Hud(string file)
        {
            ScreenCapture.CaptureScreenshot(PathOf(file), 2);
            yield return null;
            yield return null;
            yield return null;
        }

        static MazeChunk Section(int index)
        {
            foreach (var c in FindObjectsByType<MazeChunk>(FindObjectsInactive.Exclude))
                if (c.Index == index && c.Tiles != null) return c;
            return null;
        }

        static T FindInSection<T>(int index) where T : Component
        {
            foreach (var x in FindObjectsByType<T>(FindObjectsInactive.Exclude))
                if (x.GetComponentInParent<MazeChunk>() is { } c && c.Index == index) return x;
            return null;
        }

        /// <summary>Clean (no HUD) 4K render from a copy of the game camera, so post-processing matches the game.</summary>
        void Render(string file, Vector3 from, Vector3 lookAt, float fov, int w = 3840, int h = 2160)
        {
            var clone = Instantiate(Camera.main.gameObject);
            foreach (var mb in clone.GetComponents<MonoBehaviour>())
                if (mb is not UniversalAdditionalCameraData) DestroyImmediate(mb);
            foreach (var al in clone.GetComponents<AudioListener>()) DestroyImmediate(al);
            var cam = clone.GetComponent<Camera>();
            cam.fieldOfView = fov;
            clone.transform.position = from;
            clone.transform.LookAt(lookAt);

            var rt = new RenderTexture(w, h, 24) { antiAliasing = 8 };
            cam.targetTexture = rt;
            cam.Render();
            cam.targetTexture = null;
            var prev = RenderTexture.active;
            RenderTexture.active = rt;
            var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
            tex.Apply();
            RenderTexture.active = prev;
            File.WriteAllBytes(PathOf(file), tex.EncodeToPNG());
            Destroy(tex);
            rt.Release();
            Destroy(rt);
            DestroyImmediate(clone);
        }
    }
}
