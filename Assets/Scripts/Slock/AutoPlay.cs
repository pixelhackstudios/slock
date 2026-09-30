using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace Slock
{
    /// <summary>
    /// TEMPORARY automated playtest driver (not part of the game): a pellet-seeking autopilot that plays
    /// real runs and logs trajectory + events for feel analysis (stuck spots, falls, gate times).
    /// Run a player build with: Slock.x86_64 -slockauto &lt;logPath&gt; [-autotime &lt;sec&gt;] [-autoscale &lt;x&gt;]
    /// plus -batchmode -nographics for headless runs. Delete this file before shipping.
    /// </summary>
    public class AutoPlay : MonoBehaviour
    {
        public static void StartIfRequested(GameManager gm)
        {
            var args = Environment.GetCommandLineArgs();
            int i = Array.IndexOf(args, "-slockauto");
            if (i < 0) return;
            var ap = gm.gameObject.AddComponent<AutoPlay>();
            ap.gm = gm;
            ap.logPath = i + 1 < args.Length && !args[i + 1].StartsWith("-")
                ? args[i + 1]
                : Path.Combine(Application.persistentDataPath, "slockauto.log");
            ap.duration = ArgFloat(args, "-autotime", 240f);
            Time.timeScale = ArgFloat(args, "-autoscale", 2f);
        }

        static float ArgFloat(string[] args, string name, float fallback)
        {
            int i = Array.IndexOf(args, name);
            return i >= 0 && i + 1 < args.Length && float.TryParse(args[i + 1], out var v) ? v : fallback;
        }

        GameManager gm;
        TiltCameraRig rig;
        SlockController slock;
        StreamWriter log;
        string logPath;
        float duration;
        float startUnscaled;
        float nextSteer, nextSample = 1f, nextShot = 5f, nextChunkRefresh;
        Vector3 right, fwd;
        readonly List<MazeChunk> chunks = new();
        readonly Dictionary<int, bool> gateWas = new();
        Vector3 detour;
        float detourUntil;
        Vector3 lastPos;
        float lastMoveCheck;
        int stillTicks;
        float maxZ = float.MinValue;
        int gates, falls, stucks, lives = 1;
        bool quit;

        void Start()
        {
            log = new StreamWriter(logPath, false) { AutoFlush = true };
            rig = FindAnyObjectByType<TiltCameraRig>();
            slock = FindAnyObjectByType<SlockController>();
            var rot = Quaternion.Euler(rig.pitch, rig.yaw, 0f);
            right = rot * Vector3.right; right.y = 0f; right.Normalize();
            fwd = rot * Vector3.forward; fwd.y = 0f; fwd.Normalize();
            lastPos = slock.transform.position;
            startUnscaled = Time.unscaledTime;
            log.WriteLine($"EVT start t=0 timescale={Time.timeScale}");
            gm.BeginRun();
        }

        void RefreshChunks()
        {
            chunks.Clear();
            foreach (var c in FindObjectsByType<MazeChunk>(FindObjectsInactive.Exclude))
                if (c.Tiles != null) chunks.Add(c);
            chunks.Sort((a, b) => a.Index.CompareTo(b.Index));
        }

        MazeChunk ChunkAt(Vector3 p)
        {
            int want = MazeChunk.IndexAt(p.z);
            foreach (var c in chunks)
                if (c.Index == want) return c;
            return null;
        }

        void Update()
        {
            if (quit || slock == null) return;
            float now = Time.unscaledTime - startUnscaled;
            if (now >= duration) { Finish("time"); return; }
            if (now >= nextChunkRefresh) { nextChunkRefresh = now + 2f; RefreshChunks(); }

            var s = slock.transform.position;
            maxZ = Mathf.Max(maxZ, s.z);

            // Gate transitions.
            foreach (var c in chunks)
            {
                bool open = c.GateOpen;
                if (gateWas.TryGetValue(c.Index, out var was) && !was && open)
                {
                    gates++;
                    log.WriteLine($"EVT gate-open idx={c.Index} t={now:F1} pos={Fmt(s)}");
                }
                gateWas[c.Index] = open;
            }

            // Fell off? Restart a fresh life.
            int idx = MazeChunk.IndexAt(s.z);
            if (s.y < MazeChunk.FloorYOf(idx) - 4f)
            {
                falls++;
                log.WriteLine($"EVT fall n={falls} t={now:F1} pos={Fmt(s)} idx={idx}");
                NewLife();
                return;
            }

            // Stuck detection: barely moved in the last second.
            if (now >= lastMoveCheck + 1f)
            {
                float moved = Vector3.Distance(new Vector3(s.x, 0f, s.z), new Vector3(lastPos.x, 0f, lastPos.z));
                float ts = chunks.Count > 0 ? ChunkAt(s)?.TileSize ?? 1f : 1f;
                if (moved < 0.25f * ts)
                {
                    stillTicks++;
                    if (stillTicks == 3 || (stillTicks > 3 && now >= detourUntil))
                    {
                        stucks++;
                        // Sidestep: push perpendicular, alternating sides.
                        var perp = new Vector3(-(s.z - lastPos.z), 0f, s.x - lastPos.x);
                        if (perp.sqrMagnitude < 1e-6f) perp = new Vector3(-right.z, 0f, right.x);
                        detour = perp.normalized * ((stucks % 2 == 0) ? 1f : -1f);
                        detourUntil = now + 2f;
                        if (stillTicks == 3 || stillTicks % 6 == 0)
                            log.WriteLine($"EVT stuck n={stucks} t={now:F1} pos={Fmt(s)} idx={idx}");
                    }
                    if (stillTicks == 16)
                    {
                        log.WriteLine($"EVT hopeless t={now:F1} pos={Fmt(s)} idx={idx} (fresh life)");
                        NewLife();
                        return;
                    }
                }
                else { stillTicks = 0; detour = Vector3.zero; }
                lastPos = s;
                lastMoveCheck = now;
            }
            if (now > detourUntil) detour = Vector3.zero;

            if (now >= nextSteer) { nextSteer = now + 0.25f; Steer(); }

            if (now >= nextSample)
            {
                nextSample = now + 2f;
                var c = ChunkAt(s);
                log.WriteLine($"t={now:F0} pos={Fmt(s)} idx={idx} pellets={(c != null ? c.PelletsLeft : -1)} gate={(c != null ? (c.GateOpen ? "open" : "shut") : "?")}");
            }

            if (now >= nextShot)
            {
                nextShot = now + 15f;
                ScreenCapture.CaptureScreenshot($"/tmp/slockshots/auto_{now:F0}.png");
            }
        }

        void NewLife()
        {
            lives++;
            gateWas.Clear();
            detour = Vector3.zero;
            stillTicks = 0;
            gm.BeginRun();
            lastPos = slock.transform.position;
            lastMoveCheck = Time.unscaledTime - startUnscaled;
            nextSteer = lastMoveCheck + 1f;
        }

        void Steer()
        {
            var s = slock.transform.position;
            var chunk = ChunkAt(s);
            Vector3 target;
            if (chunk != null && !chunk.GateOpen)
                target = NearestPellet(chunk, s, out _) ?? chunk.TileCenter(chunk.Center, chunk.L - 1);
            else if (chunk != null)
                target = chunk.TileCenter(chunk.Center, chunk.L - 1);
            else
                target = s + Vector3.forward * 5f;

            var want = target - s;
            want.y = 0f;
            if (want.sqrMagnitude < 1e-6f) want = Vector3.forward;
            want.Normalize();
            want = (want + detour).normalized;
            float tx = Vector3.Dot(want, right), ty = Vector3.Dot(want, fwd);
            rig.overrideTilt = Vector2.ClampMagnitude(new Vector2(tx, ty) * 0.9f, 1f);
        }

        Vector3? NearestPellet(MazeChunk chunk, Vector3 s, out bool found)
        {
            Vector3? best = null;
            float bestD = float.MaxValue;
            float arrive = 0.6f * chunk.TileSize;
            foreach (var p in chunk.UneatenPelletPositions())
            {
                float d = Vector3.Distance(p, s);
                if (d < arrive || d >= bestD) continue;
                bestD = d;
                best = p;
            }
            found = best.HasValue;
            return best;
        }

        void Finish(string why)
        {
            quit = true;
            rig.overrideTilt = null;
            Time.timeScale = 1f;
            log.WriteLine($"EVT quit why={why} lives={lives} gates={gates} falls={falls} stucks={stucks} maxZ={maxZ:F1}");
            log.Close();
            Application.Quit();
        }

        static string Fmt(Vector3 v) => $"({v.x:F1},{v.y:F1},{v.z:F1})";
    }
}
