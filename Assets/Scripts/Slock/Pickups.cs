using UnityEngine;

namespace Slock
{
    /// <summary>
    /// Power gem: score, bonus time, and a few seconds where worms can be eaten.
    /// Clock (side rooms): a big chunk of time. Key (side rooms): opens this section's gate immediately.
    /// Powerups (random, instant): clear a quarter of the dots, Slock of Steel, refill slugs, one extra slug, close the holes.
    /// </summary>
    public class Pickup : MonoBehaviour
    {
        public enum Kind { Power, Clock, Key, ClearDots, Steel, RefreshSlugs, ExtraSlug, CloseTraps }
        public Kind kind;
        /// <summary>One of the random powerups (they respawn after being taken), not a gem, clock or key.</summary>
        public bool IsPowerup => kind >= Kind.ClearDots;

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
                case Kind.ClearDots: // three blue pellets in a ring
                    gem = new GameObject("Dots").transform;
                    gem.SetParent(transform, false);
                    for (int i = 0; i < 3; i++)
                    {
                        float a = i * Mathf.PI * 2f / 3f;
                        MazeChunk.Decor(PrimitiveType.Sphere, gem, new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a)) * 0.22f, Vector3.one * 0.2f, Visuals.Pellet);
                    }
                    break;
                case Kind.Steel: // a shiny steel block
                    gem = MazeChunk.Decor(PrimitiveType.Cube, transform, Vector3.zero, Vector3.one * 0.36f, Visuals.Steel).transform;
                    break;
                case Kind.RefreshSlugs: // a row of three slugs
                    gem = new GameObject("Slugs").transform;
                    gem.SetParent(transform, false);
                    for (int i = -1; i <= 1; i++)
                        MazeChunk.Decor(PrimitiveType.Cube, gem, new Vector3(i * 0.2f, 0f, 0f), Vector3.one * 0.13f, Visuals.Boost);
                    break;
                case Kind.ExtraSlug: // one big slug
                    gem = MazeChunk.Decor(PrimitiveType.Cube, transform, Vector3.zero, Vector3.one * 0.22f, Visuals.Boost).transform;
                    break;
                case Kind.CloseTraps: // a glowing green floor patch
                    gem = MazeChunk.Decor(PrimitiveType.Cube, transform, Vector3.zero, new Vector3(0.46f, 0.07f, 0.46f), Visuals.Patch).transform;
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
