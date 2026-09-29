using UnityEngine;
using UnityEngine.InputSystem;

namespace Slock
{
    /// <summary>
    /// "Tilting the world": mouse input picks a tilt, which steers the grounded slock while gravity stays vertical.
    /// The camera is rolled by the same rotation so on screen it looks like the maze tilts. Two input modes (ControlSettings):
    /// trackball (mouse movement nudges a virtual stick that stays put) or absolute (cursor offset from centre).
    /// </summary>
    public class TiltCameraRig : MonoBehaviour
    {
        [System.Serializable]
        public struct RollCommandSegment
        {
            [Min(0f)] public float forceLimitLb;
            [Min(0f)] public float gainDegPerSecPerLb;

            public RollCommandSegment(float forceLimitLb, float gainDegPerSecPerLb)
            {
                this.forceLimitLb = forceLimitLb;
                this.gainDegPerSecPerLb = gainDegPerSecPerLb;
            }
        }

        public Transform target;
        public bool inputEnabled;
        public Vector3 TiltAcceleration { get; private set; }
        /// <summary>When set, used instead of mouse/gamepad (automated playtests, demo mode).</summary>
        [System.NonSerialized] public Vector2? overrideTilt;

        [SerializeField, Tooltip("Force-to-roll-rate schedule used when F16Response is enabled. The final force limit is full input.")]
        RollCommandSegment[] f16RollCommandSchedule =
        {
            new RollCommandSegment(1f, 0f),
            new RollCommandSegment(5f, 5f),
            new RollCommandSegment(9f, 15f),
            new RollCommandSegment(17f, 30f),
        };

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
            var direction = GravityDir();
            Physics.gravity = Vector3.down * ControlSettings.FallGravity;
            TiltAcceleration = new Vector3(direction.x, 0f, direction.z) * ControlSettings.TiltAcceleration;
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
            if (pad != null)
            {
                var padStick = ControlSettings.F16Response
                    ? pad.leftStick.ReadUnprocessedValue()
                    : pad.leftStick.ReadValue();
                float activityThreshold = ControlSettings.F16Response ? 0.0004f : 0.02f;
                if (padStick.sqrMagnitude > activityThreshold) v = padStick;
            }

            float mag = Mathf.Clamp01(v.magnitude);
            if (ControlSettings.F16Response)
            {
                float shaped = EvaluateF16Response(mag);
                return v.sqrMagnitude > 0f ? v.normalized * shaped : Vector2.zero;
            }

            if (mag < deadZone) return Vector2.zero;
            // Remap past the dead zone, then curve it: small offsets give small tilts, full offset still gives full tilt.
            float t = Mathf.Pow((mag - deadZone) / (1f - deadZone), ControlSettings.ResponseCurve);
            return v.normalized * t;
        }

        float EvaluateF16Response(float magnitude)
        {
            var schedule = f16RollCommandSchedule;
            if (schedule == null || schedule.Length == 0) return Mathf.Clamp01(magnitude);

            float fullForce = Mathf.Max(0f, schedule[schedule.Length - 1].forceLimitLb);
            if (fullForce <= 0f) return 0f;

            float force = Mathf.Clamp01(magnitude) * fullForce;
            float command = IntegrateRollSchedule(force, schedule);
            float maximumCommand = IntegrateRollSchedule(fullForce, schedule);
            return maximumCommand > 0f ? Mathf.Clamp01(command / maximumCommand) : 0f;
        }

        static float IntegrateRollSchedule(float force, RollCommandSegment[] schedule)
        {
            float command = 0f;
            float previousLimit = 0f;
            foreach (var segment in schedule)
            {
                float limit = Mathf.Max(previousLimit, segment.forceLimitLb);
                float width = Mathf.Clamp(force - previousLimit, 0f, limit - previousLimit);
                command += width * Mathf.Max(0f, segment.gainDegPerSecPerLb);
                previousLimit = limit;
            }
            return command;
        }

        [ContextMenu("Log F-16 Response Samples and Continuity")]
        void LogF16ResponseSamples()
        {
            var schedule = f16RollCommandSchedule;
            if (schedule == null || schedule.Length == 0)
            {
                Debug.LogWarning("F-16 response schedule is empty.", this);
                return;
            }

            float fullForce = Mathf.Max(0f, schedule[schedule.Length - 1].forceLimitLb);
            float maximumCommand = IntegrateRollSchedule(fullForce, schedule);
            if (fullForce <= 0f || maximumCommand <= 0f)
            {
                Debug.LogWarning("F-16 response schedule has no positive full-input command.", this);
                return;
            }

            var samples = new System.Collections.Generic.List<float> { 0f };
            foreach (var segment in schedule)
            {
                float input = Mathf.Clamp01(segment.forceLimitLb / fullForce);
                if (samples[samples.Count - 1] < input) samples.Add(input);
            }
            if (samples[samples.Count - 1] < 1f) samples.Add(1f);

            foreach (float input in samples)
                Debug.Log($"F-16 response: input={input:F6}, output={EvaluateF16Response(input):F6}", this);

            float epsilon = Mathf.Min(0.001f, fullForce * 0.0001f);
            float maxGain = 0f;
            foreach (var segment in schedule)
                maxGain = Mathf.Max(maxGain, Mathf.Max(0f, segment.gainDegPerSecPerLb));
            float tolerance = epsilon * maxGain / maximumCommand + 0.000001f;

            float previousLimit = 0f;
            foreach (var segment in schedule)
            {
                float limit = Mathf.Max(previousLimit, segment.forceLimitLb);
                float input = limit / fullForce;
                float left = EvaluateF16Response(Mathf.Max(0f, (limit - epsilon) / fullForce));
                float at = EvaluateF16Response(input);
                float right = EvaluateF16Response(Mathf.Min(1f, (limit + epsilon) / fullForce));
                bool continuous = Mathf.Abs(left - at) <= tolerance && Mathf.Abs(right - at) <= tolerance;
                Debug.Log($"F-16 breakpoint {limit:F3} lb: left={left:F6}, at={at:F6}, right={right:F6}, continuous={continuous}", this);
                Debug.Assert(continuous, $"F-16 response is discontinuous at {limit:F3} lb.", this);
                previousLimit = limit;
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

            // Rotate the camera the way the world "would" have been rotated, scaled down for comfort.
            var worldTilt = Quaternion.FromToRotation(Vector3.down, GravityDir());
            var roll = Quaternion.Slerp(Quaternion.identity, worldTilt, ControlSettings.VisualTilt);
            var rot = roll * BaseRot;
            zoomNow = Mathf.Lerp(zoomNow, zoom, 1f - Mathf.Exp(-2f * Time.unscaledDeltaTime));
            transform.SetPositionAndRotation(pivot + rot * new Vector3(0, 0, -distance * zoomNow), rot);
        }

        void OnDisable()
        {
            TiltAcceleration = Vector3.zero;
            Physics.gravity = new Vector3(0, -9.81f, 0);
        }
    }
}
