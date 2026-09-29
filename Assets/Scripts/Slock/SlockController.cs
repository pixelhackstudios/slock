using UnityEngine;

namespace Slock
{
    /// <summary>
    /// The sliding block. The world's tilted gravity does all the pushing and surface friction is the only resistance;
    /// this just keeps it flush on ramps and drops it cleanly into holes.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class SlockController : MonoBehaviour
    {
        /// <summary>Width of the block: always exactly one grid block of the section it's in.</summary>
        public float Size { get; private set; } = 1f;
        public float Height => Size * 1.1f;      // a hair taller than the walls (which are Size tall)
        const float Clearance = 0.04f;           // physics box is a hair smaller (fraction of Size) so it never jams
        // Compensation for this collider's flat-face contact patch: measured (SlockResponseProbe), a sliding box here is
        // slowed by exactly twice the material's friction coefficient (PhysX friction patches use multiple contact points).
        // The material gets half of ControlSettings.Friction so that value is the real mu. Re-measure if the collider shape changes.
        const float PhysxPatchFrictionCompensation = 0.5f;
        public float shrinkSpeed = 3f;           // size units per second when passing through a gate

        float targetSize = 1f;
        float gridTs = 1f, gridZ0;               // the grid we're locked to (current section)
        BoxCollider box;
        Transform visual;

        public float holeSnap = 14f;       // how fast it lines up with a hole it's dropping into
        public float alignSpeed = 12f;

        public Rigidbody Body { get; private set; }
        public bool Grounded { get; private set; }

        const int SelfLayer = 2; // "Ignore Raycast", so our own probes skip us

        public static SlockController Create()
        {
            var go = new GameObject("Slock") { layer = SelfLayer };
            var box = go.AddComponent<BoxCollider>();
            box.material = new PhysicsMaterial("Slock")
            {
                dynamicFriction = ControlSettings.Friction * PhysxPatchFrictionCompensation,
                staticFriction = ControlSettings.Friction * PhysxPatchFrictionCompensation,
                bounciness = 0.2f,
                frictionCombine = PhysicsMaterialCombine.Minimum, // the slock's friction wins over the default 0.6 surfaces
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
            Body.linearDamping = 0f;    // no hidden drag: surface friction is the only resistance
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

            // Live-tunable from the pause screen. Friction is the only resistance: gravity does all the pushing.
            box.sharedMaterial.dynamicFriction = box.sharedMaterial.staticFriction = ControlSettings.Friction * PhysxPatchFrictionCompensation;
            var p = Body.position;
            var v = Body.linearVelocity;
            Body.constraints = RigidbodyConstraints.FreezeRotation;

            Grounded = Physics.Raycast(p, Vector3.down, out var hit, Height * 0.5f + 0.35f * Size, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore);
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

            // Safety limit only (keeps fast falls from tunnelling); not part of the feel.
            var flat = new Vector3(v.x, 0, v.z);
            if (flat.magnitude > ControlSettings.MaxSpeed)
            {
                flat = flat.normalized * ControlSettings.MaxSpeed;
                Body.linearVelocity = new Vector3(flat.x, v.y, flat.z);
            }
        }

        static float Snap(float v, float ts) => Mathf.Round(v / ts) * ts;
        float SnapZ(float z) => gridZ0 + Mathf.Round((z - gridZ0) / gridTs) * gridTs;
    }
}
