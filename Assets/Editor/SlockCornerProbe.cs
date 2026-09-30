using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using UnityEditor;
using UnityEngine;
using Slock;

/// <summary>
/// Does the shape of a wall's outside corner decide whether the slock catches on it? Runs a side opening
/// (one tile wide, in a wall along +x) with every combination of slock shape (sharp box / rounded hull) and wall
/// corner radius, and measures: how far off-centre the slock can be and still get in from rest, what the wall
/// contact is doing when it's stuck, and what happens sliding past the opening. Gravity is set directly (the tilt
/// rig is disabled; the probe moves the camera itself) so every trial sees exactly the same world. Progress and
/// results show on screen and in the Console. Any assist force on the controller (grid magnet) is switched off.
///   Unity -batchmode -projectPath . -executeMethod SlockCornerProbe.Run -logFile corners.log
/// </summary>
public static class SlockCornerProbe
{
    [MenuItem("Slock/Run Corner Probe")]
    public static void Run() => SlockResponseProbe.RunWith(typeof(SlockCornerProbeBehaviour));
}

public class SlockCornerProbeBehaviour : MonoBehaviour
{
    const float OriginX = 2000f, GapZ = 12f;
    SlockController slock;
    MeshCollider hullCol;
    BoxCollider box;
    SlockContactRecorder rec;
    readonly List<GameObject> walls = new();
    readonly List<string> shown = new();
    string status = "starting...";
    Vector2 scroll;

    /// <summary>Logs to the Console and to the on-screen results panel.</summary>
    void Report(string line)
    {
        Debug.Log("[corner] " + line);
        shown.Add(line);
    }

    IEnumerator Start()
    {
        yield return new WaitForSeconds(1f);
        slock = FindAnyObjectByType<SlockController>();
        FindAnyObjectByType<TiltCameraRig>().enabled = false;   // gravity is set directly; LateUpdate moves the camera
        FindAnyObjectByType<GameManager>().enabled = false;     // no run timer, HUD or game-over screen over the test
        hullCol = slock.transform.Find("Collider").GetComponent<MeshCollider>();
        // Sharp box for comparison, exactly the hull's size.
        box = slock.gameObject.AddComponent<BoxCollider>();
        box.sharedMaterial = hullCol.sharedMaterial;
        box.size = hullCol.transform.localScale;
        rec = slock.gameObject.AddComponent<SlockContactRecorder>();

        // Measure the physics alone: switch off any assist force on the controller (e.g. a grid magnet) if present.
        var magnet = typeof(SlockController).GetField("magnetStiffness");
        if (magnet != null)
        {
            Report($"grid magnet switched OFF for measurement (was {magnet.GetValue(slock)})");
            magnet.SetValue(slock, 0f);
        }

        var floor = GameObject.CreatePrimitive(PrimitiveType.Cube);
        floor.transform.position = new Vector3(OriginX, -0.5f, 0f);
        floor.transform.localScale = new Vector3(40f, 1f, 200f);
        // The cube is the physics floor; draw it with the game's own tiled floor instead of one stretched texture.
        floor.GetComponent<Renderer>().enabled = false;
        var floorLook = new MeshBuilder(1f, 0f, 0f);
        floorLook.Prism(OriginX - 20f, OriginX + 20f, -100f, 100f, -1f, 0f, -1f, 0f, MeshBuilder.Faces.Top);
        var floorVis = new GameObject("probe floor");
        floorVis.AddComponent<MeshFilter>().sharedMesh = floorLook.Build("probe floor");
        floorVis.AddComponent<MeshRenderer>().sharedMaterials = new[] { Visuals.FloorTop, Visuals.WallSide, Visuals.WallTop };

        float mu = ControlSettings.Friction;
        Report($"settings: gravity {ControlSettings.FallGravity}, friction {mu}, slock hull {hullCol.transform.localScale.x:0.00} tile wide");
        var offsets = new[] { 0f, 0.05f, 0.1f, 0.15f, 0.2f, 0.3f, 0.4f };

        // 1. Sliding along a plain maze-built wall. Coulomb: along-wall accel = g_z - mu*(|g_y| + |g_x|).
        BuildPlainWall();
        foreach (bool sharpSlock in new[] { true, false })
        {
            UseBox(sharpSlock);
            var row = new StringBuilder();
            foreach (float side in new[] { 0f, 12f, 24f })
            {
                status = $"1/4 wall slide: {(sharpSlock ? "sharp" : "round")} slock, pressed in at {side:0} deg";
                yield return Place(0f, Vector3.zero, G(side, 20f));
                var g = Physics.gravity;
                float v0 = 0, v1 = 0;
                for (int i = 0; i < 40; i++)
                {
                    yield return new WaitForFixedUpdate();
                    if (i == 14) v0 = slock.Body.linearVelocity.z;
                    if (i == 39) v1 = slock.Body.linearVelocity.z;
                }
                float a = (v1 - v0) / (25 * Time.fixedDeltaTime);
                float predicted = Mathf.Max(0, g.z - mu * (Mathf.Abs(g.y) + Mathf.Abs(g.x)));
                row.Append($"  pressed {side:0}deg: {a:0.0} (physics {predicted:0.0})");
            }
            Report($"wall slide accel, {(sharpSlock ? "sharp" : "round")} slock, 20deg along wall:{row}");
        }

        // 2. Breakaway: pressed against the wall, what forward tilt starts it sliding? Coulomb: tan(fwd) > mu*(1 + tan(side)).
        foreach (bool sharpSlock in new[] { true, false })
        foreach (float side in new[] { 12f, 24f })
        {
            UseBox(sharpSlock);
            float coulomb = Mathf.Atan(mu * (1f + Mathf.Tan(side * Mathf.Deg2Rad))) * Mathf.Rad2Deg;
            float found = float.NaN;
            for (float fwd = Mathf.Floor(coulomb) - 1f; fwd <= 30f; fwd += 1f)
            {
                status = $"2/4 breakaway: {(sharpSlock ? "sharp" : "round")} slock, pressed in at {side:0} deg, trying {fwd:0} deg";
                yield return Place(0f, Vector3.zero, G(side, 0f));   // settle against the wall first
                for (int i = 0; i < 15; i++) yield return new WaitForFixedUpdate();
                Physics.gravity = G(side, fwd);
                for (int i = 0; i < 40; i++) yield return new WaitForFixedUpdate();
                if (slock.Body.linearVelocity.z > 0.1f) { found = fwd; break; }
            }
            Report($"breakaway, {(sharpSlock ? "sharp" : "round")} slock pressed in at {side:0}deg: starts at {found:0}deg (physics {coulomb:0.0}deg)");
        }

        // 3. At rest beside a side opening, off-centre by dz, world tilted toward the opening.
        foreach (float tilt in new[] { 12f, 24f })
        foreach (bool sharpSlock in new[] { true, false })
        foreach (float r in new[] { 0f, 0.125f, 0.25f })
        {
            UseBox(sharpSlock);
            BuildOpening(r);
            var row = new StringBuilder();
            foreach (float dz in offsets)
            {
                status = $"3/4 side opening: tilt {tilt:0}, {(sharpSlock ? "sharp" : "round")} slock, wall corner r {r:0.000}, off-centre {dz:0.00}";
                string outcome = null;
                yield return StaticTrial(dz, tilt, o => outcome = o);
                row.Append(outcome == "IN" ? " in " : " -- ");
            }
            Report($"opening, tilt {tilt:0}deg, {(sharpSlock ? "sharp" : "round")} slock, corner r={r:0.000} | off-centre 0,.05,.1,.15,.2,.3,.4:{row}");
        }

        // 4. Running along the wall and turning into the opening: 15 deg forward plus some toward it.
        UseBox(false);
        foreach (float r in new[] { 0f, 0.25f })
        {
            BuildOpening(r);
            var row = new StringBuilder();
            foreach (float side in new[] { 6f, 12f, 24f })
            {
                status = $"4/4 turning into opening: corner r {r:0.000}, side tilt {side:0}";
                string outcome = null;
                yield return MovingTrial(side, o => outcome = o);
                row.Append($"  side {side:0}deg: {outcome}");
            }
            Report($"turn into opening, round slock, corner r={r:0.000} |{row}");
        }

        status = "DONE. Results are also in the Console. Stop Play mode when finished.";
        Debug.Log("[corner] done");
        SlockResponseProbe.Finish();
    }

    void LateUpdate()
    {
        if (slock == null) return;
        var cam = Camera.main;
        if (cam == null) return;
        var p = slock.transform.position;
        var look = p + new Vector3(1f, 0f, 0f);                    // between the slock and the wall it's testing
        cam.transform.position = look + new Vector3(-7f, 11f, -9f);
        cam.transform.LookAt(look);
    }

    void OnGUI()
    {
        GUILayout.BeginArea(new Rect(10, 10, Mathf.Min(Screen.width - 20, 1100), Screen.height * 0.6f), GUI.skin.box);
        GUILayout.Label("<b>SLOCK CORNER PROBE</b> (automated test: the mouse does nothing)   " + status, new GUIStyle(GUI.skin.label) { richText = true, fontSize = 14 });
        scroll = GUILayout.BeginScrollView(scroll);
        foreach (var line in shown) GUILayout.Label(line);
        GUILayout.EndScrollView();
        GUILayout.EndArea();
    }

    static Vector3 G(float degTowardX, float degTowardZ = 0f)
    {
        var d = new Vector3(Mathf.Tan(degTowardX * Mathf.Deg2Rad), -1f, Mathf.Tan(degTowardZ * Mathf.Deg2Rad)).normalized;
        return d * ControlSettings.FallGravity;
    }

    IEnumerator Place(float z, Vector3 v0, Vector3 g)
    {
        Physics.gravity = g;
        slock.SetSizeImmediate(1f);
        slock.SetGrid(1f, 0f);
        slock.ResetTo(new Vector3(OriginX, slock.Height * 0.5f + 0.02f, z));
        slock.Body.linearVelocity = v0;
        yield return new WaitForFixedUpdate();
        rec.Clear();
    }

    IEnumerator StaticTrial(float dz, float tilt, Action<string> result)
    {
        yield return Place(GapZ + dz, Vector3.zero, G(tilt));
        float still = 0;
        for (float t = 0; t < 3f; t += Time.fixedDeltaTime)
        {
            yield return new WaitForFixedUpdate();
            if (slock.Body.position.x - OriginX > 0.8f) { result("IN"); yield break; }
            if (t > 0.3f && slock.Body.linearVelocity.magnitude < 0.02f) still += Time.fixedDeltaTime; else still = 0;
            if (still > 0.3f) { rec.Clear(); for (int i = 0; i < 10; i++) yield return new WaitForFixedUpdate(); result("STUCK"); yield break; }
        }
        result("SLOW");
    }

    IEnumerator MovingTrial(float side, Action<string> result)
    {
        yield return Place(GapZ - 4f, Vector3.zero, G(side, 15f));
        float still = 0;
        for (float t = 0; t < 4f; t += Time.fixedDeltaTime)
        {
            yield return new WaitForFixedUpdate();
            var p = slock.Body.position;
            if (p.x - OriginX > 0.8f) { result("in"); yield break; }
            if (p.z > GapZ + 2f) { result($"passed it at {slock.Body.linearVelocity.z:0.0} m/s"); yield break; }
            if (t > 0.3f && slock.Body.linearVelocity.magnitude < 0.02f) still += Time.fixedDeltaTime; else still = 0;
            if (still > 0.3f) { result($"STUCK at z={p.z - GapZ:+0.00;-0.00} from opening centre, x={p.x - OriginX:0.00}"); yield break; }
        }
        result("timeout");
    }

    void BuildPlainWall()
    {
        foreach (var w in walls) Destroy(w);
        walls.Clear();
        // Built like the maze: one MeshBuilder prism per tile, faces hidden where a neighbour covers them
        // (MazeChunk's Hides), cooked the way MazeChunk does.
        var mb = new MeshBuilder(1f, 0f, 0f);
        for (int iz = -10; iz < 80; iz++)
        {
            var faces = MeshBuilder.Faces.Top | MeshBuilder.Faces.PosX | MeshBuilder.Faces.NegX;
            if (iz == 79) faces |= MeshBuilder.Faces.PosZ;
            if (iz == -10) faces |= MeshBuilder.Faces.NegZ;
            mb.Prism(OriginX + 0.5f, OriginX + 1.5f, iz - 0.5f, iz + 0.5f, 0f, 1f, 0f, 1f, faces);
        }
        var go = new GameObject("mazewall");
        var mc = go.AddComponent<MeshCollider>();
        mc.cookingOptions = MeshColliderCookingOptions.CookForFasterSimulation | MeshColliderCookingOptions.EnableMeshCleaning
                          | MeshColliderCookingOptions.WeldColocatedVertices | MeshColliderCookingOptions.UseFastMidphase;
        mc.sharedMesh = mb.Build("mazewall");
        go.AddComponent<MeshFilter>().sharedMesh = mc.sharedMesh;
        go.AddComponent<MeshRenderer>().sharedMaterials = new[] { Visuals.FloorTop, Visuals.WallSide, Visuals.WallTop };
        walls.Add(go);
    }

    void UseBox(bool on) { box.enabled = on; hullCol.enabled = !on; }

    void BuildOpening(float r)
    {
        foreach (var w in walls) Destroy(w);
        walls.Clear();
        // Only the two corners at the mouth of the opening are shaped; everything else stays square.
        Wall(0.5f, 1.5f, -3f, GapZ - 0.5f, 0, 0, 0, r);          // (x0,z1) corner is the mouth
        Wall(0.5f, 1.5f, GapZ + 0.5f, 60f, r, 0, 0, 0);          // (x0,z0) corner is the mouth
        Wall(1.5f, 2.5f, GapZ - 0.5f, GapZ + 0.5f, 0, 0, 0, 0);  // back of the pocket
    }

    /// <summary>Wall block with rounded vertical edges. Corner radii in order (x0,z0), (x1,z0), (x1,z1), (x0,z1).</summary>
    void Wall(float x0, float x1, float z0, float z1, float r00, float r10, float r11, float r01)
    {
        var pts = new List<Vector2>();
        void Corner(float cx, float cz, float r, float a0)
        {
            if (r <= 0f) { pts.Add(new Vector2(cx, cz)); return; }
            float sx = Mathf.Cos((a0 + 45f) * Mathf.Deg2Rad) > 0 ? -1 : 1, sz = Mathf.Sin((a0 + 45f) * Mathf.Deg2Rad) > 0 ? -1 : 1;
            var c = new Vector2(cx + sx * r, cz + sz * r);
            for (int i = 0; i <= 8; i++)
            {
                float a = (a0 + 90f * i / 8f) * Mathf.Deg2Rad;
                pts.Add(c + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * r);
            }
        }
        Corner(x0, z0, r00, 180f);
        Corner(x1, z0, r10, 270f);
        Corner(x1, z1, r11, 0f);
        Corner(x0, z1, r01, 90f);

        var verts = new List<Vector3>();
        foreach (var p in pts) { verts.Add(new Vector3(OriginX + p.x, 0f, p.y)); verts.Add(new Vector3(OriginX + p.x, 1f, p.y)); }
        var tris = new List<int>();
        int n = pts.Count;
        for (int i = 0; i < n; i++)
        {
            int j = (i + 1) % n;
            // Both windings, so the probe's walls draw from either side (the collider only uses the hull).
            tris.AddRange(new[] { 2 * i, 2 * j, 2 * i + 1, 2 * j, 2 * j + 1, 2 * i + 1 });
            tris.AddRange(new[] { 2 * i, 2 * i + 1, 2 * j, 2 * j, 2 * i + 1, 2 * j + 1 });
            if (i > 0 && i < n - 1) tris.AddRange(new[] { 0, 2 * i, 2 * j, 1, 2 * j + 1, 2 * i + 1, 0, 2 * j, 2 * i, 1, 2 * i + 1, 2 * j + 1 });
        }
        var mesh = new Mesh();
        mesh.SetVertices(verts);
        mesh.SetTriangles(tris, 0);
        mesh.RecalculateNormals();
        var go = new GameObject("wall");
        var mc = go.AddComponent<MeshCollider>();
        mc.convex = true;
        mc.sharedMesh = mesh;
        go.AddComponent<MeshFilter>().sharedMesh = mesh;
        go.AddComponent<MeshRenderer>().sharedMaterial = Visuals.WallSide;
        walls.Add(go);
    }

}

public class SlockContactRecorder : MonoBehaviour
{
    public Vector3 normalSum, impulseSum;
    public int count;
    public void Clear() { normalSum = impulseSum = Vector3.zero; count = 0; }
    void OnCollisionStay(Collision c)
    {
        for (int i = 0; i < c.contactCount; i++)
        {
            var n = c.GetContact(i).normal;
            if (Mathf.Abs(n.y) > 0.5f) continue;          // floor contacts
            normalSum += n;
            count++;
        }
        if (Mathf.Abs(c.impulse.y) < Mathf.Abs(c.impulse.x) + Mathf.Abs(c.impulse.z)) impulseSum += c.impulse;
    }
}
