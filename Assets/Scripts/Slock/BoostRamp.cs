using UnityEngine;

namespace Slock
{
    /// <summary>
    /// A side-room ramp's booster: slide down it freely, but head back up and it launches the slock to the top.
    /// </summary>
    public class BoostRamp : MonoBehaviour
    {
        /// <summary>Horizontal direction pointing uphill.</summary>
        public Vector3 up;
        public float accel = 80f;
        public float launchSpeed = 15f;

        void OnTriggerStay(Collider other)
        {
            var s = other.GetComponentInParent<SlockController>();
            if (s == null) return;
            var v = s.Body.linearVelocity;
            float along = Vector3.Dot(new Vector3(v.x, 0f, v.z), up);
            if (along > 0.3f && along < launchSpeed)
                s.Body.AddForce(up * accel, ForceMode.Acceleration);
        }
    }
}
