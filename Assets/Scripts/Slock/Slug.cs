using UnityEngine;

namespace Slock
{
    /// <summary>
    /// The slock's emergency slug: a slow glowing projectile (Slock, Slorm, Slug). One shot per run,
    /// fired with a left click along the tilt's cardinal (N/E/S/W). It flies straight at slock height,
    /// killing the first slorm it touches or blasting one wall block open, then fizzles at max range.
    /// </summary>
    public class Slug : MonoBehaviour
    {
        Vector3 dir;
        float speed, range, travelled, age;
        bool spent;

        /// <summary>Launch a slug from <paramref name="origin"/> along <paramref name="direction"/> (horizontal).</summary>
        public static Slug Fire(Transform parent, Vector3 origin, Vector3 direction, float size, float range, float speed)
        {
            var go = new GameObject("Slug");
            go.transform.SetParent(parent, false);
            go.transform.position = origin + direction * (0.6f * size);
            var slug = go.AddComponent<Slug>();
            slug.dir = direction;
            slug.range = range;
            slug.speed = speed;

            var rb = go.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            rb.useGravity = false;
            var col = go.AddComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = 0.12f * size;

            var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
            DestroyImmediate(cube.GetComponent<Collider>());
            cube.transform.SetParent(go.transform, false);
            cube.transform.localScale = Vector3.one * (0.15f * size);
            cube.GetComponent<MeshRenderer>().sharedMaterial = Visuals.Boost;
            return slug;
        }

        void Update()
        {
            if (spent) return;
            float step = speed * Time.deltaTime;
            transform.position += dir * step;
            travelled += step;
            age += Time.deltaTime;
            if (travelled >= range || age > 5f) Fizzle();
        }

        void OnTriggerEnter(Collider other)
        {
            if (spent || other == null) return;
            if (other.GetComponentInParent<SlockController>() != null) return; // our own slock
            var worm = other.GetComponentInParent<Worm>();
            if (worm != null && !worm.Eaten)
            {
                spent = true;
                GameManager.I?.OnSlugKillWorm(worm);
                Destroy(gameObject);
                return;
            }
            if (other.GetComponentInParent<Pickup>() != null) return;
            if (other.gameObject.name == "Gate") { Fizzle(); return; } // the locked gate: slugs can't open it
            if (other.GetComponentInParent<Checkpoint>() != null) return;
            if (other.GetComponentInParent<BoostRamp>() != null) return;
            if (other.isTrigger) return; // unknown trigger: pass through
            // Solid chunk mesh: blast it only if our centre is inside a main-maze wall block
            // (a graze while flying past a wall face keeps flying).
            var chunk = other.GetComponentInParent<MazeChunk>();
            if (chunk == null || chunk.Tiles == null) { Fizzle(); return; }
            var key = chunk.KeyAt(transform.position);
            int tx = key.x + chunk.Center, tz = key.y - chunk.RampTiles;
            if (tx < 0 || tx >= chunk.W || tz < 0 || tz >= chunk.L) return; // ramps/rooms: keep flying
            if (chunk.Tiles[tx, tz] == Tile.Wall)
            {
                spent = true;
                GameManager.I?.OnSlugBlastWall(chunk, tx, tz);
                Destroy(gameObject);
            }
        }

        void Fizzle()
        {
            if (spent) return;
            spent = true;
            GameManager.I?.OnSlugFizzle();
            Destroy(gameObject);
        }
    }
}
