using UnityEngine;

namespace Slock
{
    /// <summary>
    /// Player-tunable control feel, edited live from the pause screen and saved to PlayerPrefs.
    /// Read every frame by <see cref="TiltCameraRig"/> (input + tilt) and <see cref="SlockController"/> (movement).
    /// </summary>
    public static class ControlSettings
    {
        // Defaults
        const bool DefTrackball = true;
        const bool DefF16Response = false;
        const float DefSensitivity = 1f, DefCurve = 1.6f, DefRecenter = 0f, DefSmoothing = 0.06f, DefMaxTilt = 24f,
                    DefFallGravity = 45f, DefTiltAcceleration = 45f, DefSlideDrag = 1.8f, DefMaxSpeed = 16f,
                    DefLaneSpring = 70f, DefVisualTilt = 0.45f;

        /// <summary>Trackball: the (hidden) mouse nudges the tilt and it stays put. Otherwise the cursor's distance
        /// from screen centre sets the tilt.</summary>
        public static bool Trackball = DefTrackball;
        public static bool F16Response = DefF16Response;
        public static float Sensitivity = DefSensitivity;   // tilt per unit of mouse movement
        public static float ResponseCurve = DefCurve;       // 1 = linear; higher = gentler near level (fine control)
        public static float Recenter = DefRecenter;         // trackball: how fast the board drifts back to level (/s)
        public static float TiltSmoothing = DefSmoothing;   // seconds for the board to follow the input
        public static float MaxTilt = DefMaxTilt;           // degrees at full input
        public static float FallGravity = DefFallGravity;   // straight-down gravity while falling
        public static float TiltAcceleration = DefTiltAcceleration; // horizontal steering acceleration while grounded
        public static float SlideDrag = DefSlideDrag;       // how quickly it settles; tilt speed = push / drag
        public static float MaxSpeed = DefMaxSpeed;
        public static float LaneSpring = DefLaneSpring;     // how firmly it's held on its grid line
        public static float VisualTilt = DefVisualTilt;     // how much the camera tips with the board

        const string Key = "slock.controls.";

        public static void Load()
        {
            Trackball = PlayerPrefs.GetInt(Key + "trackball", DefTrackball ? 1 : 0) == 1;
            F16Response = PlayerPrefs.GetInt(Key + "f16Response", DefF16Response ? 1 : 0) == 1;
            Sensitivity = PlayerPrefs.GetFloat(Key + "sensitivity", DefSensitivity);
            ResponseCurve = PlayerPrefs.GetFloat(Key + "curve", DefCurve);
            Recenter = PlayerPrefs.GetFloat(Key + "recenter", DefRecenter);
            TiltSmoothing = PlayerPrefs.GetFloat(Key + "smoothing", DefSmoothing);
            MaxTilt = PlayerPrefs.GetFloat(Key + "maxTilt", DefMaxTilt);
            float oldGravity = PlayerPrefs.GetFloat(Key + "gravity", DefFallGravity);
            FallGravity = PlayerPrefs.GetFloat(Key + "fallGravity", oldGravity);
            TiltAcceleration = PlayerPrefs.GetFloat(Key + "tiltAcceleration", oldGravity);
            SlideDrag = PlayerPrefs.GetFloat(Key + "slideDrag", DefSlideDrag);
            MaxSpeed = PlayerPrefs.GetFloat(Key + "maxSpeed", DefMaxSpeed);
            LaneSpring = PlayerPrefs.GetFloat(Key + "laneSpring", DefLaneSpring);
            VisualTilt = PlayerPrefs.GetFloat(Key + "visualTilt", DefVisualTilt);
        }

        public static void Save()
        {
            PlayerPrefs.SetInt(Key + "trackball", Trackball ? 1 : 0);
            PlayerPrefs.SetInt(Key + "f16Response", F16Response ? 1 : 0);
            PlayerPrefs.SetFloat(Key + "sensitivity", Sensitivity);
            PlayerPrefs.SetFloat(Key + "curve", ResponseCurve);
            PlayerPrefs.SetFloat(Key + "recenter", Recenter);
            PlayerPrefs.SetFloat(Key + "smoothing", TiltSmoothing);
            PlayerPrefs.SetFloat(Key + "maxTilt", MaxTilt);
            PlayerPrefs.SetFloat(Key + "fallGravity", FallGravity);
            PlayerPrefs.SetFloat(Key + "tiltAcceleration", TiltAcceleration);
            PlayerPrefs.SetFloat(Key + "slideDrag", SlideDrag);
            PlayerPrefs.SetFloat(Key + "maxSpeed", MaxSpeed);
            PlayerPrefs.SetFloat(Key + "laneSpring", LaneSpring);
            PlayerPrefs.SetFloat(Key + "visualTilt", VisualTilt);
            PlayerPrefs.Save();
        }

        public static void ResetDefaults()
        {
            Trackball = DefTrackball;
            F16Response = DefF16Response;
            Sensitivity = DefSensitivity;
            ResponseCurve = DefCurve;
            Recenter = DefRecenter;
            TiltSmoothing = DefSmoothing;
            MaxTilt = DefMaxTilt;
            FallGravity = DefFallGravity;
            TiltAcceleration = DefTiltAcceleration;
            SlideDrag = DefSlideDrag;
            MaxSpeed = DefMaxSpeed;
            LaneSpring = DefLaneSpring;
            VisualTilt = DefVisualTilt;
            Save();
        }
    }
}
