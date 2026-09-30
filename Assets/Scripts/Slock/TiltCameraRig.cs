using UnityEngine;
using UnityEngine.InputSystem;

namespace Slock
{
    /// <summary>
    /// "Tilting the world": mouse input picks a tilt. A single tilted gravity vector drives the physics and the
    /// camera presents that exact same rotation, so apparent downhill and simulated downhill cannot diverge.
    /// One control law: mouse movement accumulates into a persistent 2D trackball state (it stays where you
    /// leave it unless recentering is enabled), a precision response shapes its magnitude
    /// (magnitude^2.2: extremely fine near neutral, full tilt at full displacement), and that commands the tilt.
    /// </summary>
    public class TiltCameraRig : MonoBehaviour
    {
        public Transform target;
        public bool inputEnabled;
        /// <summary>When set, used instead of mouse/gamepad (automated playtests, demo mode).</summary>
        [System.NonSerialized] public Vector2? overrideTilt;

        public float trackballPixels = 320f;   // mouse travel (px) from level to full tilt, at sensitivity 1

        public float yaw = 28f, pitch = 48f, distance = 20f;
        public float followSmoothing = 0.18f;
        /// <summary>Distance multiplier; eased in, so the camera closes in gently as blocks shrink.</summary>
        public float zoom = 1f;
        float zoomNow = 1f;
        public float lookAhead = 3f;

        /// <summary>Current tilt, each axis in -1..1 (x = screen right, y = screen up).</summary>
        public Vector2 Tilt { get; private set; }
        /// <summary>The persistent trackball state, -1..1 on each axis, before the precision response.</summary>
        public Vector2 Trackball => trackball;

        Vector2 trackball;
        public void ResetTrackball() => trackball = Vector2.zero;

        Vector2 tiltVel;
        Vector3 pivot, pivotVel;
        Quaternion BaseRot => Quaternion.Euler(pitch, yaw, 0f);

        public void SnapToTarget()
        {
            if (target == null) return;
            pivot = target.position;
            pivotVel = Vector3.zero;
            Tilt = Vector2.zero;
            tiltVel = Vector2.zero;
        }

        void Update()
        {
            var want = overrideTilt ?? (inputEnabled ? ReadInput() : Vector2.zero);
            Tilt = Vector2.SmoothDamp(Tilt, want, ref tiltVel, Mathf.Max(0.001f, ControlSettings.TiltSmoothing), Mathf.Infinity, Time.unscaledDeltaTime);
            // One world, one downhill direction: the force field and visible tilt are the same rotation.
            Physics.gravity = GravityDir() * ControlSettings.FallGravity;
        }

        Vector2 ReadInput()
        {
            var mouse = Mouse.current;
            float sens = Mathf.Max(0.05f, ControlSettings.Sensitivity);
            // Mouse movement accumulates into the persistent trackball state; it stays where you leave it
            // (optionally drifting back to level via Recenter).
            if (mouse != null) trackball += mouse.delta.ReadValue() * sens / trackballPixels;
            trackball = Vector2.MoveTowards(trackball, Vector2.zero, ControlSettings.Recenter * Time.unscaledDeltaTime);
            trackball = Vector2.ClampMagnitude(trackball, 1f);

            var v = trackball;
            var pad = Gamepad.current;
            if (pad != null)
            {
                var padStick = pad.leftStick.ReadValue();
                if (padStick.sqrMagnitude > 0.0004f) v = padStick;
            }

            // Precision response: direction unchanged, magnitude shaped for fine authority near
            // neutral and full commanded tilt at full displacement.
            float mag = Mathf.Clamp01(v.magnitude);
            return v.sqrMagnitude > 0f ? v.normalized * PrecisionResponse(mag) : Vector2.zero;
        }

        /// <summary>Precision response: magnitude^2.2. Zero at neutral, full scale at full displacement,
        /// extremely fine near center with continuously increasing gain outward. No dead zone, no breakpoints.</summary>
        static float PrecisionResponse(float magnitude) => Mathf.Pow(Mathf.Clamp01(magnitude), 2.2f);

        [ContextMenu("Log Precision Response Samples")]
        void LogPrecisionResponseSamples()
        {
            for (int i = 0; i <= 10; i++)
            {
                float m = i / 10f;
                Debug.Log($"Precision response: input={m:F1}, output={PrecisionResponse(m):F6}", this);
            }
        }

        Vector3 GravityDir()
        {
            var rot = BaseRot;
            var right = Flat(rot * Vector3.right);
            var fwd = Flat(rot * Vector3.forward);
            float tx = Mathf.Tan(Tilt.x * ControlSettings.MaxTilt * Mathf.Deg2Rad);
            float ty = Mathf.Tan(Tilt.y * ControlSettings.MaxTilt * Mathf.Deg2Rad);
            return (Vector3.down + right * tx + fwd * ty).normalized;
        }

        static Vector3 Flat(Vector3 v) { v.y = 0f; return v.normalized; }

        void LateUpdate()
        {
            if (target == null) return;

            var goal = target.position + Vector3.forward * lookAhead;
            pivot = Vector3.SmoothDamp(pivot, goal, ref pivotVel, followSmoothing, Mathf.Infinity, Time.unscaledDeltaTime);

            // Present exactly the same tilt that physics is using. Scaling this independently makes
            // the player see one downhill direction while the Rigidbody experiences another.
            var worldTilt = Quaternion.FromToRotation(Vector3.down, GravityDir());
            var rot = worldTilt * BaseRot;
            zoomNow = Mathf.Lerp(zoomNow, zoom, 1f - Mathf.Exp(-2f * Time.unscaledDeltaTime));
            transform.SetPositionAndRotation(pivot + rot * new Vector3(0, 0, -distance * zoomNow), rot);
        }

        void OnDisable() => Physics.gravity = new Vector3(0, -9.81f, 0);
    }
}
