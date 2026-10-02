using UnityEngine;

namespace Slock
{
    /// <summary>
    /// A ramp booster: head uphill and it speeds the slock up the ramp, then at the top launches it in a hop over
    /// whatever is in between, landing on <see cref="landing"/> (4 blocks past the top). Slide down and it's guided
    /// to a stop by <see cref="downStop"/> (2 blocks into the room), if set. Either way the player then has it back.
    /// Used on side-room return ramps and on the entry climb ramp past each gate.
    /// </summary>
    public class BoostRamp : MonoBehaviour
    {
        /// <summary>Horizontal direction pointing uphill.</summary>
        public Vector3 up;
        public float accel = 80f;
        public float launchSpeed = 15f;
        public Vector3 top;            // a point on the ramp's top edge
        public Vector3 landing;        // floor centre of the block the launch lands on
        public float hop;              // how high the launch must clear (a wall)
        public Vector3? downStop;

        void OnTriggerStay(Collider other)
        {
            var s = other.GetComponentInParent<SlockController>();
            if (s == null || s.Launching) return;
            var v = s.Body.linearVelocity;
            float along = Vector3.Dot(new Vector3(v.x, 0f, v.z), up);
            if (along > 0.3f)
            {
                if (Vector3.Dot(s.Body.position - top, up) >= 0f) s.Launch(landing, hop);
                else if (along < launchSpeed) s.Body.AddForce(up * accel, ForceMode.Acceleration);
            }
            else if (along < -0.3f && downStop.HasValue)
                s.Guide(-up, downStop.Value);
        }
    }
}
