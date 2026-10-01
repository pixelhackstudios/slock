using Unity.Collections;
using UnityEngine;

namespace Slock
{
    /// <summary>
    /// The sliding block. Tilted gravity pushes; floor/ramp friction is the only drag. Wall contacts are frictionless
    /// and squared to the grid so panel seams don't snag the slide. It stays on tile-centre rails and turns
    /// Pac-Man style at centres.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class SlockController : MonoBehaviour
    {
        /// <summary>Width of the block: always exactly one grid block of the section it's in.</summary>
        public float Size { get; private set; } = 1f;
        public float Height => Size * 1.1f;      // a hair taller than the walls (which are Size tall)
        const float Shrink = 0.1f;              // hull undersize vs a tile (1%): stops wedging, stays grid-true
        // Compensation for this collider's flat-face contact patch: measured (coast test on a level floor), a sliding box here is
        // slowed by exactly twice the material's friction coefficient (PhysX friction patches use multiple contact points).
        // The material gets half of ControlSettings.Friction so that value is the real mu. Re-measure if the collider shape changes.
        const float PhysxPatchFrictionCompensation = 0.5f;
        // Creep: a soft, jelly-like resistance at low speed (strongest near rest, gone by CreepFadeSpeed). A gentle
        // tilt settles into a steady creep that grows with the slope (a wide, human-sized band: ~0.2 tiles/s just
        // past friction up to ~2 tiles/s); tilt past ~12 deg and it breaks free into a normal slide
        // (breakaway accel = CreepDamping * CreepFadeSpeed / 4).
        const float CreepDamping = 6f;           // per second, at rest
        const float CreepFadeSpeed = 6f;         // tiles/s
        public float shrinkSpeed = 3f;           // size units per second when passing through a gate

        float targetSize = 1f;
        float gridTs = 1f, gridZ0;               // the grid we're locked to (current section)
        Transform hull;                          // the single convex collision body (a child so it can scale with the slock)
        Collider hullCollider;
        Transform visual;

        public float holeSnap = 14f;       // how fast it lines up with a hole it's dropping into
        public float alignSpeed = 12f;
        public float turnSnap = 14f;         // how fast it slides to a tile centre to take a turn
        public float turnBias = 1.15f;       // tilt must favour the other axis by this much to turn (no jitter on diagonals)
        bool travelZ = true;                 // rail it's on: true = runs along Z (X locked), false = runs along X (Z locked)
        float prevFlatSpeed;                 // snag trace: detect sudden scrub

        public Rigidbody Body { get; private set; }
        public bool Grounded { get; private set; }

        const int SelfLayer = 2; // "Ignore Raycast", so our own probes skip us

        public static SlockController Create()
        {
            var go = new GameObject("Slock") { layer = SelfLayer };

            // One convex, rounded-corner collision hull (the low-poly jelly, slightly inset) so wall corners and
            // ramp lips deflect the block instead of snagging it like a sharp box would.
            var hullGo = new GameObject("Collider") { layer = SelfLayer };
            hullGo.transform.SetParent(go.transform, false);
            var hullCollider = hullGo.AddComponent<MeshCollider>();
            hullCollider.convex = true;
            hullCollider.material = new PhysicsMaterial("Slock")
            {
                dynamicFriction = ControlSettings.Friction * PhysxPatchFrictionCompensation,
                staticFriction = ControlSettings.Friction * PhysxPatchFrictionCompensation,
                bounciness = 0f,
                frictionCombine = PhysicsMaterialCombine.Minimum, // the slock's friction wins over the default 0.6 surfaces
                bounceCombine = PhysicsMaterialCombine.Maximum,
            };

            // Jelly body: the rounded Blender cube if present (Resources/Slock/SlockJelly.fbx), else a plain cube.
            var hullMesh = Resources.Load<Mesh>("Slock/SlockJellyLow") ?? Resources.Load<Mesh>("Slock/SlockJelly");
            var body = new GameObject("Jelly") { layer = SelfLayer };
            body.transform.SetParent(go.transform, false);
            var jellyMesh = Resources.Load<Mesh>("Slock/SlockJelly");
            if (jellyMesh == null)
            {
                var tmp = GameObject.CreatePrimitive(PrimitiveType.Cube);
                jellyMesh = tmp.GetComponent<MeshFilter>().sharedMesh;
                Destroy(tmp);
            }
            hullCollider.sharedMesh = hullMesh != null ? hullMesh : jellyMesh; // the full jelly is over PhysX's convex limit
            hullCollider.hasModifiableContacts = true; // so wall-side friction can be cleared
            body.AddComponent<MeshFilter>().sharedMesh = jellyMesh;
            body.AddComponent<MeshRenderer>().sharedMaterial = Visuals.SlockJelly;
            // A darker core you can see through the jelly, for depth.
            var core = new GameObject("Core");
            core.transform.SetParent(body.transform, false);
            core.transform.localScale = Vector3.one * 0.5f;
            core.AddComponent<MeshFilter>().sharedMesh = jellyMesh;
            var coreRenderer = core.AddComponent<MeshRenderer>();
            coreRenderer.sharedMaterial = Visuals.SlockCore;
            coreRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;


            var s = go.AddComponent<SlockController>();
            s.hull = hullGo.transform;
            s.hullCollider = hullCollider;
            s.visual = body.transform;
            s.SetSizeImmediate(1f);
            return s;
        }

        /// <summary>Which grid to lock to: the current section's block size and its tile-centre origin on Z.</summary>
        public void SetGrid(float tileSize, float z0) { gridTs = tileSize; gridZ0 = z0; }

        /// <summary>Shrink (smoothly) to a new block size, e.g. when passing through a gate.</summary>
        public void ShrinkTo(float size) => targetSize = size;

        public void SetSizeImmediate(float size)
        {
            targetSize = size;
            ApplySize(size);
        }

        void ApplySize(float size)
        {
            Size = size;
            float s = size * (1f - Shrink);
            hull.localScale = new Vector3(s, Height, s);
            visual.localScale = new Vector3(size, Height, size);
        }

        void Awake()
        {
            Body = GetComponent<Rigidbody>();
            Body.mass = 1f;
            Body.linearDamping = 0f;    // no hidden drag: floor friction is the only resistance
            Body.angularDamping = 5f;
            Body.constraints = RigidbodyConstraints.FreezeRotation;
            Body.interpolation = RigidbodyInterpolation.Interpolate;
            Body.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        }

        void OnEnable()
        {
            Physics.ContactModifyEvent += SquareWallContacts;
            Physics.ContactModifyEventCCD += SquareWallContactsCCD;
        }

        void OnDisable()
        {
            Physics.ContactModifyEvent -= SquareWallContacts;
            Physics.ContactModifyEventCCD -= SquareWallContactsCCD;
        }

        /// <summary>
        /// Floor/ramp (normal mostly up) are left alone. Wall contacts get no friction, and their normal is squared
        /// to the nearest grid axis: the maze mesh is separate triangles per tile, and where two flush wall panels
        /// meet PhysX treats the seam as an edge and pushes along the hull's bevel (~15° back along the rail), which
        /// braked the slide. Every maze wall faces ±X or ±Z, so squaring the normal costs nothing real.
        /// </summary>
        static void SquareWallContacts(PhysicsScene _, NativeArray<ModifiableContactPair> pairs) => Square(pairs, false);
        static void SquareWallContactsCCD(PhysicsScene _, NativeArray<ModifiableContactPair> pairs) => Square(pairs, true);

        static bool traceRailZ = true; // snag trace: which way along-rail is, for the physics callback

        static void Square(NativeArray<ModifiableContactPair> pairs, bool ccd)
        {
            for (int i = 0; i < pairs.Length; i++)
            {
                var pair = pairs[i];
                for (int c = 0; c < pair.contactCount; c++)
                {
                    var n = pair.GetNormal(c);
                    if (SnagTrace.Enabled)
                    {
                        // Anything pushing along the rail can brake the slide: walls past ~3°, floor past ~9°.
                        float alongN = Mathf.Abs(traceRailZ ? n.z : n.x);
                        if (alongN > (Mathf.Abs(n.y) >= 0.5f ? 0.15f : 0.05f))
                            SnagTrace.RawContact(pair.GetPoint(c), n, pair.GetSeparation(c), ccd, traceRailZ);
                    }
                    if (Mathf.Abs(n.y) >= 0.5f) continue;
                    pair.SetDynamicFriction(c, 0f);
                    pair.SetStaticFriction(c, 0f);
                    pair.SetNormal(c, Mathf.Abs(n.x) >= Mathf.Abs(n.z)
                        ? new Vector3(Mathf.Sign(n.x), 0f, 0f)
                        : new Vector3(0f, 0f, Mathf.Sign(n.z)));
                }
            }
        }

        public void ResetTo(Vector3 position)
        {
            Body.position = position;
            Body.rotation = Quaternion.identity;
            transform.SetPositionAndRotation(position, Quaternion.identity);
            Body.linearVelocity = Vector3.zero;
            Body.angularVelocity = Vector3.zero;
        }

        public void Knock(Vector3 direction, float speed)
        {
            direction.y = 0f;
            Body.AddForce(direction.normalized * speed + Vector3.up * 2f, ForceMode.VelocityChange);
        }

        /// <summary>Bounce away from <paramref name="fromPosition"/> hard enough to slide about
        /// <paramref name="tiles"/> grid blocks (3 by default), plus a small hop.</summary>
        public void BounceBack(Vector3 fromPosition, float tiles = 3f)
        {
            var away = transform.position - fromPosition;
            away.y = 0f;
            if (away.sqrMagnitude < 1e-6f)
            {
                away = Body.linearVelocity;
                away.y = 0f;
            }
            if (away.sqrMagnitude < 1e-6f) away = Vector3.back;
            away.Normalize();
            // v = sqrt(2*a*d): friction is the only resistance, so this slides ~tiles blocks.
            float a = Mathf.Max(0.5f, ControlSettings.Friction * ControlSettings.FallGravity);
            float speed = Mathf.Sqrt(2f * a * tiles * Size);
            speed = Mathf.Clamp(speed, 2.5f, 12f);
            Body.linearVelocity = new Vector3(away.x * speed, Body.linearVelocity.y, away.z * speed);
            Body.AddForce(Vector3.up * 2f, ForceMode.VelocityChange);
        }

        void FixedUpdate()
        {
            if (!Mathf.Approximately(Size, targetSize))
                ApplySize(Mathf.MoveTowards(Size, targetSize, shrinkSpeed * Time.fixedDeltaTime));

            SnagTrace.Flush();
            var p = Body.position;
            var v = Body.linearVelocity;

            // Surface friction (live-tunable from the pause screen); gravity does all the pushing.
            var mat = hullCollider.sharedMaterial;
            mat.staticFriction = mat.dynamicFriction = ControlSettings.Friction * PhysxPatchFrictionCompensation;
            Body.constraints = RigidbodyConstraints.FreezeRotation;

            Grounded = Physics.Raycast(p, Vector3.down, out var hit, Height * 0.5f + 0.35f * Size, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore);
            if (!Grounded && Physics.Raycast(p, Vector3.down, Height * 0.5f + 1.5f * Size, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore))
            {
                // Only briefly airborne (hopping off a ramp's lip, a bump): floor is right below, so this isn't a
                // hole. Keep its speed and stay on its rail.
                Body.constraints = RigidbodyConstraints.FreezeRotation |
                    (travelZ ? RigidbodyConstraints.FreezePositionX : RigidbodyConstraints.FreezePositionZ);
                return;
            }
            if (!Grounded)
            {
                // Centre is over a hole (or past an edge): line up with that grid square and drop straight
                // through it, instead of catching a corner and wedging.
                var target = new Vector3(Snap(p.x, gridTs), p.y, SnapZ(p.z));
                var pull = (target - p) * holeSnap;
                Body.linearVelocity = new Vector3(pull.x, v.y, pull.z);
                return;
            }

            // Stay flush with ramps.
            var targetRot = Quaternion.FromToRotation(Vector3.up, hit.normal);
            Body.MoveRotation(Quaternion.Slerp(Body.rotation, targetRot, alignSpeed * Time.fixedDeltaTime));

            // Rails: the bottom centre is locked to the tile-centre line across the corridor (a real physics
            // constraint, so gravity and friction along the corridor stay exact). It turns Pac-Man style: when
            // the tilt favours the other axis and that way is open from the nearest tile centre, it slides to
            // that centre and switches rails.
            var g = Physics.gravity;
            bool wantZ = travelZ;
            if (Mathf.Abs(g.z) > Mathf.Abs(g.x) * turnBias) wantZ = true;
            else if (Mathf.Abs(g.x) > Mathf.Abs(g.z) * turnBias) wantZ = false;

            float along = travelZ ? p.z : p.x;
            float alongCentre = travelZ ? SnapZ(p.z) : Snap(p.x, gridTs);
            if (wantZ != travelZ)
            {
                var centrePos = travelZ ? new Vector3(p.x, p.y, alongCentre) : new Vector3(alongCentre, p.y, p.z);
                var dir = wantZ ? new Vector3(0f, 0f, Mathf.Sign(g.z)) : new Vector3(Mathf.Sign(g.x), 0f, 0f);
                if (!Probe(centrePos, dir, gridTs * 0.7f))
                {
                    if (Mathf.Abs(alongCentre - along) < 0.02f * gridTs)
                    {
                        // At the centre: switch rails. Momentum along the old rail stops at the corner.
                        travelZ = wantZ;
                        p = centrePos;
                        Body.position = p;
                        v = travelZ ? new Vector3(0f, v.y, v.z) : new Vector3(v.x, v.y, 0f);
                        Body.linearVelocity = v;
                    }
                    else
                    {
                        float pull = (alongCentre - along) * turnSnap;
                        v = travelZ ? new Vector3(v.x, v.y, pull) : new Vector3(pull, v.y, v.z);
                        Body.linearVelocity = v;
                    }
                }
            }

            // Hold the cross axis exactly on the tile-centre line.
            if (travelZ)
            {
                float x = Snap(p.x, gridTs);
                if (!Mathf.Approximately(p.x, x)) Body.position = new Vector3(x, p.y, p.z);
                Body.linearVelocity = new Vector3(0f, v.y, v.z);
                Body.constraints = RigidbodyConstraints.FreezeRotation | RigidbodyConstraints.FreezePositionX;
            }
            else
            {
                float z = SnapZ(p.z);
                if (!Mathf.Approximately(p.z, z)) Body.position = new Vector3(p.x, p.y, z);
                Body.linearVelocity = new Vector3(v.x, v.y, 0f);
                Body.constraints = RigidbodyConstraints.FreezeRotation | RigidbodyConstraints.FreezePositionZ;
            }
            v = Body.linearVelocity;
            var flat = new Vector3(v.x, 0, v.z);

            // Creep (see CreepDamping): soft resistance that fades out as it speeds up.
            float sp = flat.magnitude, fade = CreepFadeSpeed * gridTs;
            if (sp > 1e-4f && sp < fade)
                Body.AddForce(-flat * (CreepDamping * (1f - sp / fade)), ForceMode.Acceleration);

            // Safety limit only (keeps fast falls from tunnelling); not part of the feel.
            if (flat.magnitude > ControlSettings.MaxSpeed)
            {
                flat = flat.normalized * ControlSettings.MaxSpeed;
                Body.linearVelocity = new Vector3(flat.x, v.y, flat.z);
            }

            traceRailZ = travelZ;
            TraceCorner();
            float flatSp = new Vector3(Body.linearVelocity.x, 0f, Body.linearVelocity.z).magnitude;
            if (Grounded && prevFlatSpeed > 1.5f && flatSp < prevFlatSpeed * 0.85f)
            {
                SnagTrace.Event("speed_drop",
                    $"from={prevFlatSpeed:F2} to={flatSp:F2} pos=({Body.position.x:F2},{Body.position.z:F2}) rail={(travelZ ? "Z" : "X")}");
            }
            prevFlatSpeed = flatSp;
        }

        Vector2Int traceFrontCell = new(int.MinValue, int.MinValue);

        /// <summary>Snag trace: log each time the front edge enters a tile where a side wall starts or ends.</summary>
        void TraceCorner()
        {
            if (!SnagTrace.Enabled || GameManager.I == null) return;
            var p = Body.position;
            var v = Body.linearVelocity;
            float alongV = travelZ ? v.z : v.x;
            if (Mathf.Abs(alongV) < 0.2f) return;
            var chunk = GameManager.I.ChunkAt(p.z);
            if (chunk == null || chunk.Tiles == null) return;

            var dir = travelZ ? new Vector3(0f, 0f, Mathf.Sign(alongV)) : new Vector3(Mathf.Sign(alongV), 0f, 0f);
            var side = travelZ ? new Vector3(-dir.z, 0f, 0f) : new Vector3(0f, 0f, dir.x); // left of travel
            var front = p + dir * (Size * 0.5f * (1f - Shrink));
            var cell = chunk.KeyAt(front);
            if (cell == traceFrontCell) return;
            bool first = traceFrontCell.x == int.MinValue;
            traceFrontCell = cell;
            if (first) return;

            char T(Vector3 w)
            {
                var k = chunk.KeyAt(w);
                int tx = k.x + chunk.Center, tz = k.y - chunk.RampTiles;
                if (!chunk.InBounds(tx, tz)) return '-';
                return chunk.Tiles[tx, tz] switch { Tile.Wall => 'W', Tile.Floor => 'F', _ => 'V' };
            }
            float ts = chunk.TileSize;
            var centre = new Vector3(cell.x * ts, p.y, chunk.Z0 + cell.y * ts);
            char lb = T(centre - dir * ts + side * ts), la = T(centre + side * ts);
            char rb = T(centre - dir * ts - side * ts), ra = T(centre - side * ts);
            if (lb == la && rb == ra) return; // straight wall both sides: no corner here
            float drift = travelZ ? p.x - Snap(p.x, gridTs) : p.z - SnapZ(p.z);
            SnagTrace.Event("corner",
                $"cell=({cell.x},{cell.y}) L={lb}>{la} R={rb}>{ra} drift={drift:F3} spd={Mathf.Abs(alongV):F2} " +
                $"pos=({p.x:F2},{p.z:F2}) rail={(travelZ ? "Z" : "X")}");
        }

        void OnCollisionEnter(Collision collision)
        {
            LogWallContacts("wall_hit", collision);
        }

        void OnCollisionStay(Collision collision)
        {
            LogWallContacts("wall_scrub", collision);
        }

        void LogWallContacts(string kind, Collision collision)
        {
            if (!SnagTrace.Enabled || collision == null) return;
            var vel = Body.linearVelocity;
            for (int i = 0; i < collision.contactCount; i++)
            {
                var c = collision.GetContact(i);
                if (Mathf.Abs(c.normal.y) >= 0.97f) continue; // flat floor (tilted floor contacts are logged: seam suspects)
                SnagTrace.Wall(kind, c.point, c.normal, c.impulse.magnitude, vel, travelZ);
            }
        }

        static float Snap(float v, float ts) => Mathf.Round(v / ts) * ts;

        static bool Probe(Vector3 from, Vector3 dir, float dist) =>
            Physics.Raycast(from, dir, dist, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore);
        float SnapZ(float z) => gridZ0 + Mathf.Round((z - gridZ0) / gridTs) * gridTs;
    }
}
