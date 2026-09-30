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
        // Tuned by playtest (2026-09-29): the best-feeling set so far.
        const float DefSensitivity = 1f, DefRecenter = 0f, DefSmoothing = 0.25f, DefMaxTilt = 20f,
                    DefFallGravity = 60f, DefFriction = 0.052f, DefSpeedLimit = 60f;

        public static float Sensitivity = DefSensitivity;   // tilt per unit of mouse movement
        public static float Recenter = DefRecenter;         // how fast the trackball drifts back to level (/s)
        public static float TiltSmoothing = DefSmoothing;   // seconds for the board to follow the input
        public static float MaxTilt = DefMaxTilt;           // degrees of actual world/camera tilt at full input
        public static float FallGravity = DefFallGravity;   // magnitude of the tilted world gravity vector
        public static float Friction = DefFriction;         // surface friction coefficient (0 = ice); the only thing that slows it
        public static float MaxSpeed = DefSpeedLimit;       // safety limit only, well above what gravity reaches

        const string Key = "slock.controls.";

        public static void Load()
        {
            Sensitivity = PlayerPrefs.GetFloat(Key + "sensitivity", DefSensitivity);
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
            PlayerPrefs.SetFloat(Key + "sensitivity", Sensitivity);
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
            Sensitivity = DefSensitivity;
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
