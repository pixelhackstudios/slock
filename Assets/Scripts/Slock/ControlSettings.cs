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
                    DefFallGravity = 45f, DefFriction = 0.05f, DefSpeedLimit = 40f;

        /// <summary>Trackball: the (hidden) mouse nudges the tilt and it stays put. Otherwise the cursor's distance
        /// from screen centre sets the tilt.</summary>
        public static bool Trackball = DefTrackball;
        public static bool F16Response = DefF16Response;
        public static float Sensitivity = DefSensitivity;   // tilt per unit of mouse movement
        public static float ResponseCurve = DefCurve;       // 1 = linear; higher = gentler near level (fine control)
        public static float Recenter = DefRecenter;         // trackball: how fast the board drifts back to level (/s)
        public static float TiltSmoothing = DefSmoothing;   // seconds for the board to follow the input
        public static float MaxTilt = DefMaxTilt;           // degrees of actual world/camera tilt at full input
        public static float FallGravity = DefFallGravity;   // magnitude of the tilted world gravity vector
        public static float Friction = DefFriction;         // surface friction coefficient (0 = ice); the only thing that slows it
        public static float MaxSpeed = DefSpeedLimit;       // safety limit only, well above what gravity reaches

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
            Friction = PlayerPrefs.GetFloat(Key + "friction", DefFriction);
            MaxSpeed = PlayerPrefs.GetFloat(Key + "speedLimit", DefSpeedLimit);
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
            PlayerPrefs.SetFloat(Key + "friction", Friction);
            PlayerPrefs.SetFloat(Key + "speedLimit", MaxSpeed);
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
            Friction = DefFriction;
            MaxSpeed = DefSpeedLimit;
            Save();
        }
    }
}
