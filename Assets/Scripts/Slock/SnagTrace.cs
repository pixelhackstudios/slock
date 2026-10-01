using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace Slock
{
    /// <summary>
    /// Flight recorder for slide snags. Writes <c>snag-trace.log</c> next to the Assets folder.
    /// Play, hit snags, then we read that file. Set <see cref="Enabled"/> false when done.
    /// </summary>
    public static class SnagTrace
    {
        public const bool Enabled = true;

        static readonly string FilePath =
            Path.GetFullPath(Path.Combine(Application.dataPath, "..", "snag-trace.log"));

        static float t0;
        static readonly List<string> pending = new();   // raw contacts from the physics callback, written on the main thread
        static float lastWallLog = -999f;

        public static void BeginRun()
        {
            if (!Enabled) return;
            t0 = Time.time;
            lastWallLog = -999f;
            File.WriteAllText(FilePath,
                "# snag-trace.log — t(sec) event fields\n" +
                "# wall_hit / wall_scrub: side contact (ny = normal.y, |ny|<0.5 means wall)\n" +
                "# speed_drop: flat speed fell >15% in one physics step while grounded\n" +
                "# corner: the slock's front crossed into a tile where a side wall starts or ends (L/R: W wall, F floor, V void,\n" +
                "#         before>after); drift = off the rail centre line; spd = speed this step\n" +
                "# raw_contact: contact as PhysX made it, BEFORE squaring, that pushes along the rail (ccd = continuous sweep)\n" +
                "# rail_turn: axis switch; carried = speed taken round the corner, from = speed before\n" +
                $"# started {System.DateTime.Now:o}\n");
            Debug.Log($"[SnagTrace] writing {FilePath}");
        }

        public static void Event(string name, string fields)
        {
            if (!Enabled) return;
            float t = Time.time - t0;
            try { File.AppendAllText(FilePath, $"{t:F3}\t{name}\t{fields}\n"); }
            catch (IOException) { /* editor reimport can briefly lock the file */ }
        }

        /// <summary>Queue a contact from the contact-modify callback (may run off the main thread).</summary>
        public static void RawContact(Vector3 point, Vector3 normal, float separation, bool ccd, bool railZ)
        {
            if (!Enabled) return;
            string line = $"pos={point.x:F2},{point.y:F2},{point.z:F2} n=({normal.x:F2},{normal.y:F2},{normal.z:F2}) " +
                          $"sep={separation:F3} ccd={(ccd ? 1 : 0)} rail={(railZ ? "Z" : "X")}";
            lock (pending) pending.Add(line);
        }

        /// <summary>Write queued raw contacts (call from FixedUpdate).</summary>
        public static void Flush()
        {
            if (!Enabled) return;
            lock (pending)
            {
                foreach (var line in pending) Event("raw_contact", line);
                pending.Clear();
            }
        }

        /// <summary>Side-wall contacts. Scrubs are rate-limited; hard hits always log.</summary>
        public static void Wall(string kind, Vector3 point, Vector3 normal, float impulse, Vector3 vel, bool travelZ)
        {
            if (!Enabled) return;
            float t = Time.time - t0;
            bool hard = impulse > 0.05f || kind == "wall_hit";
            if (!hard && t - lastWallLog < 0.08f) return;
            lastWallLog = t;
            float flat = new Vector3(vel.x, 0f, vel.z).magnitude;
            Event(kind,
                $"pos={point.x:F2},{point.y:F2},{point.z:F2} ny={normal.y:F2} n=({normal.x:F2},{normal.z:F2}) " +
                $"imp={impulse:F3} spd={flat:F2} v=({vel.x:F2},{vel.z:F2}) rail={(travelZ ? "Z" : "X")}");
        }
    }
}
