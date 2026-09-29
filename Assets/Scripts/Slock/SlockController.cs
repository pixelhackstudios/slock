using UnityEngine;

namespace Slock
{
    /// <summary>
    /// The sliding block. The world's tilted gravity does the pushing; this keeps it locked
    /// to the grid: it always travels along a row or column, corners Pac-Man style, and drops cleanly into holes.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class SlockController : MonoBehaviour
    {
        /// <summary>Width of the block: always exactly one grid block of the section it's in.</summary>
        public float Size { get; private set; } = 1f;
        public float Height => Size * 1.1f;      // a hair taller than the walls (which are Size tall)
        const float Clearance = 0.04f;           // physics box is a hair smaller (fraction of Size) so it never jams
        public float shrinkSpeed = 3f;           // size units per second when passing through a gate

        float targetSize = 1f;
        float gridTs = 1f, gridZ0;               // the grid we're locked to (current section)
        BoxCollider box;
        Transform visual;

        public float laneSpring = 70f;     // how hard the block is held on its grid line
        public float laneDamping = 12f;
        public float holeSnap = 14f;       // how fast it lines up with a hole it's dropping into
        public float turnBias = 1.15f;     // tilt must favour a new axis by this much before switching (no jitter on diagonals)

        bool wantZ = true;
        public float maxSpeed = 16f;
        /// <summary>Sliding drag. Tilt sets the speed it settles at (tilt accel / drag): higher = tighter, slower top speed.</summary>
        public float slideDrag = 1.8f;
        public float alignSpeed = 12f;

        public Rigidbody Body { get; private set; }
        public bool OnRail { get; private set; }
        public bool Grounded { get; private set; }

        const int SelfLayer = 2; // "Ignore Raycast", so our own probes skip us

        public static SlockController Create()
        {
            var go = new GameObject("Slock") { layer = SelfLayer };
            var box = go.AddComponent<BoxCollider>();
            box.material = new PhysicsMaterial("Slock Ice")
            {
                dynamicFriction = 0f,
                staticFriction = 0f,
                bounciness = 0.2f,
                frictionCombine = PhysicsMaterialCombine.Minimum,
                bounceCombine = PhysicsMaterialCombine.Maximum,
            };

            // Jelly body: the rounded Blender cube if present (Resources/Slock/SlockJelly.fbx), else a plain cube.
            var body = new GameObject("Jelly") { layer = SelfLayer };
            body.transform.SetParent(go.transform, false);
            var jellyMesh = Resources.Load<Mesh>("Slock/SlockJelly");
            if (jellyMesh == null)
            {
                var tmp = GameObject.CreatePrimitive(PrimitiveType.Cube);
                jellyMesh = tmp.GetComponent<MeshFilter>().sharedMesh;
                Destroy(tmp);
            }
            body.AddComponent<MeshFilter>().sharedMesh = jellyMesh;
            body.AddComponent<MeshRenderer>().sharedMaterial = Visuals.SlockJelly;
            var jelly = body.AddComponent<JellyWobble>();
            // A darker core you can see through the jelly, for depth.
            var core = new GameObject("Core");
            core.transform.SetParent(body.transform, false);
            core.transform.localScale = Vector3.one * 0.5f;
            core.AddComponent<MeshFilter>().sharedMesh = jellyMesh;
            var coreRenderer = core.AddComponent<MeshRenderer>();
            coreRenderer.sharedMaterial = Visuals.SlockCore;
            coreRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            jelly.core = core.transform;


            var s = go.AddComponent<SlockController>();
            s.box = box;
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
            box.size = new Vector3(size * (1f - Clearance), Height, size * (1f - Clearance));
            visual.localScale = new Vector3(size, Height, size);
        }

        void Awake()
        {
            Body = GetComponent<Rigidbody>();
            Body.mass = 1f;
            Body.linearDamping = 0.05f; // sliding drag is applied horizontally in FixedUpdate so falls aren't slowed
            Body.angularDamping = 5f;
            Body.constraints = RigidbodyConstraints.FreezeRotation;
            Body.interpolation = RigidbodyInterpolation.Interpolate;
            Body.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
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

        void FixedUpdate()
        {
            if (!Mathf.Approximately(Size, targetSize))
                ApplySize(Mathf.MoveTowards(Size, targetSize, shrinkSpeed * Time.fixedDeltaTime));

            // Feel settings are live-tunable from the pause screen.
            slideDrag = ControlSettings.SlideDrag;
            maxSpeed = ControlSettings.MaxSpeed;
            laneSpring = ControlSettings.LaneSpring;
            laneDamping = 1.6f * Mathf.Sqrt(laneSpring);   // firm but not bouncy
            var p = Body.position;
            float ts = gridTs;

            var v = Body.linearVelocity;
            var g = Physics.gravity;
            Body.constraints = RigidbodyConstraints.FreezeRotation;

            Grounded = Physics.Raycast(p, Vector3.down, out var hit, Height * 0.5f + 0.35f * Size, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore);
            if (!Grounded)
            {
                // Centre is over a hole (or past an edge): line up with that grid square and drop straight
                // through it, instead of catching a corner and wedging.
                var target = new Vector3(Snap(p.x, ts), p.y, SnapZ(p.z));
                var pull = (target - p) * holeSnap;
                Body.linearVelocity = new Vector3(pull.x, v.y, pull.z);
                OnRail = true;
                return;
            }

            // Speed follows tilt: drag balances the tilt's pull, so a small tilt creeps and a full tilt races,
            // and levelling the board brings the block to a stop in about half a second.
            Body.AddForce(new Vector3(-v.x, 0f, -v.z) * slideDrag, ForceMode.Acceleration);

            // Stay flush with ramps.
            var targetRot = Quaternion.FromToRotation(Vector3.up, hit.normal);
            Body.MoveRotation(Quaternion.Slerp(Body.rotation, targetRot, alignSpeed * Time.fixedDeltaTime));

            // Grid lock: the block always travels along a row or column, like Pac-Man. Tilting toward a wall
            // while sliding keeps it sliding along its row, and it turns into the first opening that way.
            float gx = Mathf.Abs(g.x), gz = Mathf.Abs(g.z);
            if (gz > gx * turnBias) wantZ = true;
            else if (gx > gz * turnBias) wantZ = false;
            bool tilted = Mathf.Max(gx, gz) > 0.8f;
            bool movingZ = Mathf.Abs(v.z) >= Mathf.Abs(v.x);
            bool sliding = new Vector2(v.x, v.z).magnitude > 0.3f;

            bool travelZ;
            if (!tilted) travelZ = sliding ? movingZ : wantZ;
            else
            {
                var want = wantZ ? new Vector3(0, 0, Mathf.Sign(g.z)) : new Vector3(Mathf.Sign(g.x), 0, 0);
                bool blocked = Probe(p, want, ts * 0.7f);
                travelZ = blocked && sliding && movingZ != wantZ ? movingZ : wantZ;
            }

            // Hold the other axis on the grid line, cancelling gravity's sideways pull so it sits exactly on it.
            var lockAxis = travelZ ? Vector3.right : Vector3.forward;
            float c = Vector3.Dot(p, lockAxis);
            float d = (travelZ ? Snap(c, ts) : SnapZ(c)) - c;
            Body.AddForce(lockAxis * (d * laneSpring - Vector3.Dot(v, lockAxis) * laneDamping - Vector3.Dot(g, lockAxis)), ForceMode.Acceleration);
            OnRail = true;

            var flat = new Vector3(v.x, 0, v.z);
            if (flat.magnitude > maxSpeed)
            {
                flat = flat.normalized * maxSpeed;
                Body.linearVelocity = new Vector3(flat.x, v.y, flat.z);
            }
        }

        static float Snap(float v, float ts) => Mathf.Round(v / ts) * ts;
        float SnapZ(float z) => gridZ0 + Mathf.Round((z - gridZ0) / gridTs) * gridTs;

        static bool Probe(Vector3 from, Vector3 dir, float dist) =>
            Physics.Raycast(from, dir, dist, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore);
    }
}
