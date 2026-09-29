using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;
using Slock;

/// <summary>
/// Measures how the slock responds to the tilted world, using the real SlockController and TiltCameraRig on a
/// flat test floor. Editor closed:
///   Unity -batchmode -projectPath . -executeMethod SlockResponseProbe.Run -logFile probe.log
/// Set SLOCK_PROBE_OUT to a folder for the per-tick CSVs. Summary lines are logged with the prefix [probe].
/// </summary>
public static class SlockResponseProbe
{
    static EnterPlayModeOptions savedOptions;
    static bool savedEnabled;

    [MenuItem("Slock/Run Response Probe")]
    public static void Run()
    {
        savedEnabled = EditorSettings.enterPlayModeOptionsEnabled;
        savedOptions = EditorSettings.enterPlayModeOptions;
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload | EnterPlayModeOptions.DisableSceneReload;
        EditorApplication.playModeStateChanged += OnState;
        EditorApplication.EnterPlaymode();
    }

    static void OnState(PlayModeStateChange s)
    {
        if (s == PlayModeStateChange.EnteredPlayMode)
            new GameObject("Probe").AddComponent<SlockResponseProbeBehaviour>();
    }

    public static void Finish()
    {
        EditorApplication.playModeStateChanged -= OnState;
        EditorSettings.enterPlayModeOptionsEnabled = savedEnabled;
        EditorSettings.enterPlayModeOptions = savedOptions;
        if (Application.isBatchMode) EditorApplication.Exit(0);
        else EditorApplication.ExitPlaymode();
    }
}

public class SlockResponseProbeBehaviour : MonoBehaviour
{
    struct Sample
    {
        public float t, cmd, tilt, gx, gy, gz, vx, vy, vz, ax, az, px, pz;
        public bool grounded;
    }

    const float OriginX = 1000f;
    SlockController slock;
    TiltCameraRig rig;
    Vector2 dirFwd, dirRight;      // tilt-space vectors that push toward +z and +x
    readonly List<Sample> log = new();
    string outDir;
    float initialVz, startZ;

    IEnumerator Start()
    {
        outDir = Environment.GetEnvironmentVariable("SLOCK_PROBE_OUT") ?? Path.Combine(Application.temporaryCachePath, "probe");
        Directory.CreateDirectory(outDir);

        yield return new WaitForSeconds(1f);
        slock = FindAnyObjectByType<SlockController>();
        rig = FindAnyObjectByType<TiltCameraRig>();
        var floor = GameObject.CreatePrimitive(PrimitiveType.Cube);
        floor.transform.position = new Vector3(OriginX, -0.5f, 0f);
        floor.transform.localScale = new Vector3(200f, 1f, 400f);

        float y = rig.yaw * Mathf.Deg2Rad;
        var flatFwd = new Vector2(Mathf.Sin(y), Mathf.Cos(y));
        var flatRight = new Vector2(Mathf.Cos(y), -Mathf.Sin(y));
        // GravityDir: Tilt.x -> camera-right, Tilt.y -> camera-forward. Express +z and +x in those terms.
        dirFwd = new Vector2(Vector2.Dot(new Vector2(0, 1), flatRight), Vector2.Dot(new Vector2(0, 1), flatFwd));
        dirRight = new Vector2(Vector2.Dot(new Vector2(1, 0), flatRight), Vector2.Dot(new Vector2(1, 0), flatFwd));

        Debug.Log($"[probe] maxTilt={ControlSettings.MaxTilt} gravity={ControlSettings.FallGravity} friction={ControlSettings.Friction} " +
                  $"speedLimit={ControlSettings.MaxSpeed} smoothing={ControlSettings.TiltSmoothing} fixedDt={Time.fixedDeltaTime}");

        // E0: friction calibration on the game's own default floor: coast from 10 m/s, exact physics decel = mu * |g|.
        float keep = ControlSettings.Friction;
        foreach (float mu in new[] { 0.05f, 0.1f, 0.2f })
        {
            ControlSettings.Friction = mu;
            initialVz = 10f;
            yield return Scenario("coast", 1.5f, t => Vector2.zero);
            initialVz = 0f;
            float a = (Mean(0.1f, 0.2f, s => s.vz) - Mean(0.4f, 0.5f, s => s.vz)) / 0.3f;
            Debug.Log($"[probe] friction check: requested mu={mu:0.00} -> measured effective mu {a / ControlSettings.FallGravity:0.000}");
        }
        ControlSettings.Friction = keep;

        // E1: step response and release at several tilts, straight down +z.
        foreach (float m in new[] { 0.1f, 0.25f, 0.5f, 1f })
        {
            yield return Scenario($"step_{m:0.00}", 4f, t => t < 0.5f ? Vector2.zero : (t < 3f ? dirFwd * m : Vector2.zero));
            Analyse($"step_{m:0.00}", 0.5f, 3f);
        }
        // E2: reversal.
        yield return Scenario("reverse", 6f, t => t < 0.5f ? Vector2.zero : (t < 3f ? dirFwd : -dirFwd));
        AnalyseReversal("reverse", 3f);
        // E3: diagonal tilt (equal +z and +x): which lane it commits to and how well it holds it.
        yield return Scenario("diagonal", 4f, t => t < 0.5f ? Vector2.zero : (dirFwd + dirRight) * 0.5f);
        // (wall-free floor: slock heads where gravity points)
        AnalyseDiagonal("diagonal");

        // E4/E5: snagging. Same tests with the old sharp box and with the rounded hull.
        foreach (bool legacyBox in new[] { true, false })
        {
            UseLegacyBox(legacyBox);
            string label = legacyBox ? "sharp box" : "rounded hull";
            floor.SetActive(false);
            var seamFloor = BuildBlockFloor(30, 30);
            initialVz = 10f;
            yield return Scenario("seams", 2.5f, t => Vector2.zero);
            initialVz = 0f;
            float vStart = Mean(0.1f, 0.2f, s => s.vz), vEnd = Mean(2.3f, 2.4f, s => s.vz);
            float expected = ControlSettings.Friction * ControlSettings.FallGravity * 2.2f;
            float maxVy = MaxAbs(s => s.vy);
            Debug.Log($"[probe] seams ({label}): coasting over {seamFloor.name}: speed {vStart:0.00} -> {vEnd:0.00}, friction alone predicts loss {expected:0.00}, actual loss {vStart - vEnd:0.00} m/s | worst bounce {maxVy:0.000} m/s vertical");
            Destroy(seamFloor);

            // Entering a side opening while not perfectly centred on it. Wall along +x with a one-tile gap at z=11.5..12.5;
            // the slock starts at rest beside the gap (offset dz from its centre) and the world tilts toward the gap.
            floor.SetActive(true);
            var walls = new List<GameObject>();
            void Block(float x0, float x1, float z0, float z1)
            {
                var w = GameObject.CreatePrimitive(PrimitiveType.Cube);
                w.transform.position = new Vector3(OriginX + (x0 + x1) * 0.5f, 0.5f, (z0 + z1) * 0.5f);
                w.transform.localScale = new Vector3(x1 - x0, 1f, z1 - z0);
                walls.Add(w);
            }
            Block(0.5f, 1.5f, -3f, 11.5f);
            Block(0.5f, 1.5f, 12.5f, 40f);
            Block(1.5f, 2.5f, 11.5f, 12.5f);
            var results = new StringBuilder();
            foreach (float dz in new[] { 0f, 0.02f, 0.04f, 0.06f, 0.08f, 0.10f, 0.14f })
            {
                startZ = 12f + dz;
                yield return Scenario("opening", 2.5f, t => dirRight * 0.5f);
                float xEnd = log[log.Count - 1].px;
                results.Append($" dz={dz:0.00}: {(xEnd > 0.8f ? "IN" : "STUCK")}({xEnd:0.00})");
            }
            startZ = 0f;
            Debug.Log($"[probe] side opening, offset from centre -> entered? ({label}):{results}");
            foreach (var w in walls) Destroy(w);
        }
        UseLegacyBox(false);

        SlockResponseProbe.Finish();
    }


    GameObject BuildBlockFloor(int nx, int nz)
    {
        // The game's own floor construction: one prism per tile through MeshBuilder, cooked as the maze does.
        var mb = new MeshBuilder(1f, 0f, 0f);
        for (int ix = -nx / 2; ix < nx / 2; ix++)
            for (int iz = 0; iz < nz; iz++)
                mb.Prism(OriginX + ix - 0.5f, OriginX + ix + 0.5f, iz - 0.5f, iz + 0.5f, -1f, 0f, -1f, 0f, MeshBuilder.Faces.Top);
        var go = new GameObject("blockfloor");
        var mc = go.AddComponent<MeshCollider>();
        mc.cookingOptions = MeshColliderCookingOptions.CookForFasterSimulation | MeshColliderCookingOptions.EnableMeshCleaning
                          | MeshColliderCookingOptions.WeldColocatedVertices | MeshColliderCookingOptions.UseFastMidphase;
        mc.sharedMesh = mb.Build("blockfloor");
        return go;
    }

    BoxCollider legacyBox;
    void UseLegacyBox(bool on)
    {
        var hull = slock.transform.Find("Collider");
        var hullCol = hull.GetComponent<MeshCollider>();
        hullCol.enabled = !on;
        if (legacyBox == null)
        {
            legacyBox = slock.gameObject.AddComponent<BoxCollider>();
            legacyBox.sharedMaterial = hullCol.sharedMaterial;
        }
        legacyBox.enabled = on;
        legacyBox.size = new Vector3(0.96f, 1.1f, 0.96f);
    }

    IEnumerator Scenario(string name, float duration, Func<float, Vector2> command)
    {
        log.Clear();
        rig.inputEnabled = false;
        slock.SetSizeImmediate(1f);
        slock.SetGrid(1f, 0f);
        slock.ResetTo(new Vector3(OriginX, slock.Height * 0.5f + 0.02f, startZ));
        rig.overrideTilt = Vector2.zero;
        rig.SnapToTarget();
        slock.Body.linearVelocity = new Vector3(0, 0, initialVz);
        yield return new WaitForFixedUpdate();

        float t0 = Time.fixedTime;
        var last = slock.Body.linearVelocity;
        while (Time.fixedTime - t0 < duration)
        {
            float t = Time.fixedTime - t0;
            var c = command(t);
            rig.overrideTilt = c;
            slock.SetGrid(1f, 0f);
            yield return new WaitForFixedUpdate();
            var v = slock.Body.linearVelocity;
            var g = Physics.gravity;
            var p = slock.Body.position;
            float dt = Time.fixedDeltaTime;
            log.Add(new Sample
            {
                t = Time.fixedTime - t0, cmd = c.magnitude, tilt = rig.Tilt.magnitude,
                gx = g.x, gy = g.y, gz = g.z, vx = v.x, vy = v.y, vz = v.z,
                ax = (v.x - last.x) / dt, az = (v.z - last.z) / dt, px = p.x - OriginX, pz = p.z,
                grounded = slock.Grounded,
            });
            last = v;
        }
        rig.overrideTilt = Vector2.zero;

        var sb = new StringBuilder("t,cmd,tilt,gx,gy,gz,vx,vy,vz,ax,az,px,pz,grounded\n");
        var ci = CultureInfo.InvariantCulture;
        foreach (var s in log)
            sb.AppendLine(string.Join(",", Array.ConvertAll(new[] { s.t, s.cmd, s.tilt, s.gx, s.gy, s.gz, s.vx, s.vy, s.vz, s.ax, s.az, s.px, s.pz },
                f => f.ToString("0.####", ci))) + "," + (s.grounded ? 1 : 0));
        File.WriteAllText(Path.Combine(outDir, name + ".csv"), sb.ToString());
    }

    float TimeWhere(float from, float to, Func<Sample, bool> pred)
    {
        foreach (var s in log) if (s.t >= from && s.t <= to && pred(s)) return s.t;
        return float.NaN;
    }

    float Mean(float from, float to, Func<Sample, float> f)
    {
        float sum = 0; int n = 0;
        foreach (var s in log) if (s.t >= from && s.t <= to) { sum += f(s); n++; }
        return n > 0 ? sum / n : float.NaN;
    }

    /// <summary>
    /// Exact physics for a block on a flat floor under tilted gravity g, friction mu: along-floor acceleration is
    /// |g_h| - mu*|g_y| while sliding (static friction holds it if |g_h| &lt;= mu*|g_y|), directed along g's horizontal part.
    /// Integrates that over the logged gravity and compares with the measured speed.
    /// </summary>
    void Analyse(string name, float pushStart, float pushEnd)
    {
        float mu = ControlSettings.Friction;
        float vPred = 0f, worst = 0f, worstT = 0f;
        var ax = new List<float>();
        float dt = Time.fixedDeltaTime;
        foreach (var s in log)
        {
            float gh = new Vector2(s.gx, s.gz).magnitude, gn = Mathf.Abs(s.gy);
            float dir = Mathf.Sign(s.gz == 0 ? 1f : s.gz);
            float a = gh > mu * gn ? gh - mu * gn : 0f;
            if (vPred > 0f || a > 0f) vPred = Mathf.Max(0f, vPred + (a - (a == 0f ? mu * gn : 0f)) * dt);
            float vMeas = new Vector2(s.vx, s.vz).magnitude;
            if (s.t > 0.5f && Mathf.Abs(vMeas - vPred) > worst) { worst = Mathf.Abs(vMeas - vPred); worstT = s.t; }
        }
        float gEnd = Mean(pushEnd - 0.3f, pushEnd, s => s.gz), gyEnd = Mean(pushEnd - 0.3f, pushEnd, s => s.gy);
        float tiltDeg = Mathf.Atan2(gEnd, -gyEnd) * Mathf.Rad2Deg;
        float vMid = Mean(pushEnd - 0.1f, pushEnd, s => s.vz), vPredMid = 0f;
        float tStop = TimeWhere(pushEnd, log[log.Count - 1].t, s => Mathf.Abs(s.vz) < 0.05f) - pushEnd;
        float zRel = 0f; foreach (var s in log) if (s.t >= pushEnd) { zRel = s.pz; break; }
        Debug.Log($"[probe] {name}: tilt={tiltDeg:0.0}deg | speed at end of push {vMid:0.00} m/s | " +
                  $"measured vs exact-physics speed: worst gap {worst:0.000} m/s (at t={worstT:0.00}) | " +
                  $"after level: stops in {tStop * 1000:0}ms, coasts {log[log.Count - 1].pz - zRel:0.00}m | max sideways drift {MaxAbs(s => s.px):0.000}m");
    }

    float MaxAbs(Func<Sample, float> f) { float m = 0; foreach (var s in log) m = Mathf.Max(m, Mathf.Abs(f(s))); return m; }

    void AnalyseReversal(string name, float flipT)
    {
        float vBefore = Mean(flipT - 0.3f, flipT, s => s.vz);
        float tZero = TimeWhere(flipT, flipT + 3f, s => s.vz <= 0f) - flipT;
        float tG = TimeWhere(flipT, flipT + 3f, s => s.gz <= -0.9f * ControlSettings.FallGravity * Mathf.Sin(ControlSettings.MaxTilt * Mathf.Deg2Rad)) - flipT;
        float vAfter = Mean(log[log.Count - 1].t - 0.5f, log[log.Count - 1].t, s => s.vz);
        float tRev90 = TimeWhere(flipT, flipT + 3f, s => s.vz <= 0.9f * vAfter) - flipT;
        Debug.Log($"[probe] {name}: v before flip {vBefore:0.00} | gravity reaches reversed 90% in {tG * 1000:0}ms | velocity crosses zero in {tZero * 1000:0}ms | " +
                  $"reaches 90% of reverse speed ({vAfter:0.00}) in {tRev90 * 1000:0}ms");
    }

    void AnalyseDiagonal(string name)
    {
        var last = log[log.Count - 1];
        float gx = Mean(0.6f, 1.2f, s => s.gx), gz = Mean(0.6f, 1.2f, s => s.gz);
        float vx = Mean(1.1f, 1.2f, s => s.vx), vz = Mean(1.1f, 1.2f, s => s.vz);
        float gAng = Mathf.Atan2(gx, gz) * Mathf.Rad2Deg, vAng = Mathf.Atan2(vx, vz) * Mathf.Rad2Deg;
        Debug.Log($"[probe] {name}: gravity heading {gAng:0.0}deg, velocity heading {vAng:0.0}deg (open floor, so they should match) | v=({vx:0.00},{vz:0.00})");
    }
}
