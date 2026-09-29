using UnityEngine;
using UnityEngine.InputSystem;

namespace Slock
{
    /// <summary>
    /// "Tilting the world": mouse input picks a tilt, which bends gravity toward that screen direction. The camera
    /// is rolled by the same rotation so on screen it looks like the maze tilts. Two input modes (ControlSettings):
    /// trackball (mouse movement nudges a virtual stick that stays put) or absolute (cursor offset from centre).
    /// </summary>
    public class TiltCameraRig : MonoBehaviour
    {
        public Transform target;
        public bool inputEnabled;
        /// <summary>When set, used instead of mouse/gamepad (automated playtests, demo mode).</summary>
        [System.NonSerialized] public Vector2? overrideTilt;

        public float deadZone = 0.04f;
        public float mouseRange = 0.16f;       // absolute mode: fraction of screen height for full tilt, at sensitivity 1
        public float trackballPixels = 320f;   // trackball mode: mouse travel (px) from level to full tilt, at sensitivity 1

        public float yaw = 28f, pitch = 48f, distance = 20f;
        public float followSmoothing = 0.18f;
        /// <summary>Distance multiplier; eased in, so the camera closes in gently as blocks shrink.</summary>
        public float zoom = 1f;
        float zoomNow = 1f;
        public float lookAhead = 3f;

        /// <summary>Current tilt, each axis in -1..1 (x = screen right, y = screen up).</summary>
        public Vector2 Tilt { get; private set; }
        /// <summary>The raw input position (the virtual stick in trackball mode), -1..1, before the response curve.</summary>
        public Vector2 Stick => stick;

        Vector2 stick;
        public void ResetStick() => stick = Vector2.zero;

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
            Physics.gravity = GravityDir() * ControlSettings.Gravity;
        }

        Vector2 ReadInput()
        {
            var mouse = Mouse.current;
            float sens = Mathf.Max(0.05f, ControlSettings.Sensitivity);
            if (ControlSettings.Trackball)
            {
                // Mouse movement nudges the stick; it stays where you leave it (optionally drifting back to level).
                if (mouse != null) stick += mouse.delta.ReadValue() * sens / trackballPixels;
                stick = Vector2.MoveTowards(stick, Vector2.zero, ControlSettings.Recenter * Time.unscaledDeltaTime);
            }
            else if (mouse != null)
            {
                float scale = Mathf.Min(Screen.width, Screen.height) * mouseRange / sens;
                stick = (mouse.position.ReadValue() - new Vector2(Screen.width, Screen.height) * 0.5f) / scale;
            }
            stick = Vector2.ClampMagnitude(stick, 1f);

            var v = stick;
            var pad = Gamepad.current;
            if (pad != null && pad.leftStick.ReadValue().sqrMagnitude > 0.02f)
                v = pad.leftStick.ReadValue();

            float mag = Mathf.Clamp01(v.magnitude);
            if (mag < deadZone) return Vector2.zero;
            // Remap past the dead zone, then curve it: small offsets give small tilts, full offset still gives full tilt.
            float t = Mathf.Pow((mag - deadZone) / (1f - deadZone), ControlSettings.ResponseCurve);
            return v.normalized * t;
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

            // Rotate the camera the way the world "would" have been rotated, scaled down for comfort.
            var worldTilt = Quaternion.FromToRotation(Vector3.down, GravityDir());
            var roll = Quaternion.Slerp(Quaternion.identity, worldTilt, ControlSettings.VisualTilt);
            var rot = roll * BaseRot;
            zoomNow = Mathf.Lerp(zoomNow, zoom, 1f - Mathf.Exp(-2f * Time.unscaledDeltaTime));
            transform.SetPositionAndRotation(pivot + rot * new Vector3(0, 0, -distance * zoomNow), rot);
        }

        void OnDisable() => Physics.gravity = new Vector3(0, -9.81f, 0);
    }
}
