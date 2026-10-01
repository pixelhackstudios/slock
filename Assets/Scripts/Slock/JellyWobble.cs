using UnityEngine;

namespace Slock
{
    /// <summary>
    /// Makes a slorm segment wobble like jelly (visual only; the physics never changes):
    /// the top sways behind the bottom when the block speeds up, stops or turns, and the whole
    /// block squishes and springs back when it smacks into a wall or lands.
    /// </summary>
    [RequireComponent(typeof(MeshFilter))]
    public class JellyWobble : MonoBehaviour
    {
        public Transform core;

        [Header("Sway (top lags behind the bottom)")]
        public float swayGain = 0.012f;      // sway per unit of acceleration
        public float swayMax = 0.32f;
        public float swayStiffness = 260f;   // spring stiffness: higher = faster wobble
        public float swayDamping = 5f;       // lower = wobbles longer

        [Header("Squish (on impacts)")]
        public float squishGain = 0.05f;     // squish per unit of impact speed
        public float squishMax = 0.32f;
        public float squishStiffness = 380f;
        public float squishDamping = 7f;
        public float impactThreshold = 1.5f; // sudden speed change (per physics step) that counts as a smack

        Rigidbody body;                      // physics-driven (the slock); otherwise we follow the transform (worms)
        MeshRenderer rend;
        Vector3 lastPos;
        bool deformed;
        Mesh mesh;
        Vector3[] baseVerts, verts;
        Vector3 lastVel;
        Vector2 sway, swayVel;
        float squish, squishVel;
        Vector3 squishAxis = Vector3.up;     // local axis the block is being squashed along

        void Start()
        {
            body = GetComponentInParent<Rigidbody>();
            if (body != null && body.isKinematic) body = null;   // kinematic bodies report no velocity
            rend = GetComponent<MeshRenderer>();
            lastPos = transform.position;
            var mf = GetComponent<MeshFilter>();
            if (!mf.sharedMesh.isReadable)
            {
                Debug.LogWarning("JellyWobble: mesh isn't readable (enable Read/Write on the model); wobble disabled.");
                enabled = false;
                return;
            }
            mesh = Instantiate(mf.sharedMesh);   // our own copy to deform
            mesh.MarkDynamic();
            mf.sharedMesh = mesh;
            baseVerts = mesh.vertices;
            verts = new Vector3[baseVerts.Length];
            if (body != null) lastVel = body.linearVelocity;
        }

        /// <summary>Squish along <paramref name="normal"/> (world space) for an impact of <paramref name="speed"/>.</summary>
        public void Hit(Vector3 normal, float speed)
        {
            if (speed < 0.6f) return;
            var local = transform.InverseTransformDirection(normal);
            squishAxis = local.sqrMagnitude > 1e-4f ? local.normalized : Vector3.up;
            squishVel += Mathf.Min(speed * squishGain * 60f, 12f);
        }

        void FixedUpdate()
        {
            if (body != null) Step(body.linearVelocity, Time.fixedDeltaTime);
        }

        void Update()
        {
            if (body != null) return;
            float dt = Time.deltaTime;
            var p = transform.position;
            if (dt > 0f) Step((p - lastPos) / dt, dt);
            lastPos = p;
        }

        void Step(Vector3 v, float dt)
        {
            var dv = v - lastVel;
            var accel = dv / dt;
            lastVel = v;

            // A wall hit (or landing) shows up as a sudden change in velocity: squish along it.
            // (Collision events don't work here: maze floor and walls are one collider we're always touching.)
            if (dv.magnitude > impactThreshold) Hit(dv, dv.magnitude);

            // Sway: the top wants to lean against the acceleration (inertia), on a bouncy spring.
            var localA = transform.InverseTransformDirection(accel);
            var target = Vector2.ClampMagnitude(new Vector2(-localA.x, -localA.z) * swayGain, swayMax);
            swayVel += (swayStiffness * (target - sway) - swayDamping * swayVel) * dt;
            sway = Vector2.ClampMagnitude(sway + swayVel * dt, swayMax);

            squishVel += (-squishStiffness * squish - squishDamping * squishVel) * dt;
            squish = Mathf.Clamp(squish + squishVel * dt, -squishMax, squishMax);
        }

        void LateUpdate()
        {
            if (mesh == null) return;
            // Skip the vertex work when nobody can see it, or when it's settled and already reset.
            bool still = sway.sqrMagnitude < 1e-7f && swayVel.sqrMagnitude < 1e-6f && Mathf.Abs(squish) < 1e-4f && Mathf.Abs(squishVel) < 1e-3f;
            if ((rend != null && !rend.isVisible) || (still && !deformed)) return;
            deformed = !still;
            var n = squishAxis;
            for (int i = 0; i < baseVerts.Length; i++)
            {
                var p = baseVerts[i];
                // Squish: shorter along the hit axis, bulging out the other ways (roughly keeps volume).
                float along = Vector3.Dot(p, n);
                var across = p - n * along;
                p = n * (along * (1f - squish)) + across * (1f + squish * 0.5f);
                // Sway: shear grows with height, curved so the base stays planted.
                float h = Mathf.Clamp01(p.y + 0.5f);
                h *= h;
                p.x += sway.x * h;
                p.z += sway.y * h;
                verts[i] = p;
            }
            mesh.vertices = verts;
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();

            if (core != null) // the core rides along, about half as much
                core.localPosition = new Vector3(sway.x, 0f, sway.y) * 0.3f;
        }

        void OnDestroy()
        {
            if (mesh != null) Destroy(mesh);
        }
    }
}
