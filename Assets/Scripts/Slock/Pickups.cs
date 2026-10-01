using UnityEngine;

namespace Slock
{
    /// <summary>
    /// Power gem: score, bonus time, and a few seconds where worms can be eaten.
    /// Clock (side rooms): a big chunk of time. Key (side rooms): opens this section's gate immediately.
    /// </summary>
    public class Pickup : MonoBehaviour
    {
        public enum Kind { Power, Clock, Key }
        public Kind kind;

        Transform gem;
        float phase;

        void Start()
        {
            switch (kind)
            {
                case Kind.Clock: // a tall glowing cyan crystal
                    gem = MazeChunk.Decor(PrimitiveType.Cube, transform, Vector3.zero, new Vector3(0.28f, 0.6f, 0.28f), Visuals.Clock).transform;
                    break;
                case Kind.Key: // a magenta cube with a bar through it
                    gem = MazeChunk.Decor(PrimitiveType.Cube, transform, Vector3.zero, Vector3.one * 0.32f, Visuals.Key).transform;
                    MazeChunk.Decor(PrimitiveType.Cube, gem, Vector3.zero, new Vector3(2.2f, 0.3f, 0.3f), Visuals.Key);
                    break;
                default: // a big glowing power pellet
                    gem = MazeChunk.Decor(PrimitiveType.Sphere, transform, Vector3.zero, Vector3.one * 0.46f, Visuals.Pickup).transform;
                    break;
            }
            phase = Random.value * 10f;
        }

        void Update()
        {
            phase += Time.deltaTime;
            gem.localRotation = kind == Kind.Power ? Quaternion.Euler(45f, phase * 120f, 45f) : Quaternion.Euler(0f, phase * 150f, 0f);
            gem.localPosition = Vector3.up * (Mathf.Sin(phase * 3f) * 0.12f);
        }

        void OnTriggerEnter(Collider other)
        {
            if (other.GetComponentInParent<SlockController>() == null) return;
            GameManager.I?.OnPickup(this);
            Destroy(gameObject);
        }
    }

    /// <summary>End-of-chunk gate: first touch awards a time and score bonus.</summary>
    public class Checkpoint : MonoBehaviour
    {
        public int ChunkIndex;
        bool used;

        void OnTriggerEnter(Collider other)
        {
            if (used || other.GetComponentInParent<SlockController>() == null) return;
            used = true;
            GameManager.I?.OnCheckpoint(ChunkIndex);
        }
    }
}
