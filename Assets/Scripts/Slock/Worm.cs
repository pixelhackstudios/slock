using System.Collections.Generic;
using UnityEngine;

namespace Slock
{
    /// <summary>
    /// A slorm: a green block worm that inches through the maze like a telescope: the slock-sized head slides one block
    /// and pauses, and each smaller block behind eases toward the one in front of it, tucking in behind (and
    /// inside) the head; when the head moves on, the tail stretches back out. Nothing rotates: the blocks stay
    /// square to the grid. The head is solid jelly: the slock cannot pass through it. Touching it bounces the slock
    /// back and costs time, unless a power gem is active, in which case the head goes soft (trigger) and gets eaten.
    /// </summary>
    public class Worm : MonoBehaviour
    {
        static readonly float[] SegmentScale = { 0.8f, 0.66f, 0.54f, 0.44f }; // body blocks, relative to the head
        const float MoveShare = 0.6f;   // of each step: 60% sliding to the next block, 40% paused there
        const float CatchUp = 6f;       // how quickly each body block closes in on the one ahead

        MazeChunk chunk;
        Vector2Int from, to, home;
        float t, stepTime, size, height;
        System.Random rng;
        readonly List<Transform> body = new();
        readonly List<MeshRenderer> jellies = new();
        readonly List<Renderer> allRenderers = new();
        readonly List<Vector2Int> options = new(4);
        bool eaten;
        float respawnAt;
        int look = -1;
        SphereCollider col;

        public bool Eaten => eaten;
        /// <summary>Total time this slorm has taken from the player and still owes back on being eaten.</summary>
        public float stolenTime;

        public void Init(MazeChunk c, Vector2Int start, float tilesPerSecond, int seed)
        {
            chunk = c;
            size = c.TileSize;
            height = size * 1.1f;         // same as the slock
            stepTime = 1f / tilesPerSecond;
            from = to = home = start;
            rng = new System.Random(seed);

            // Physics lives on the root (kinematic body that moves with the head).
            // Solid jelly when dangerous (slock bounces off); a soft trigger when edible so it can be eaten.
            transform.position = Pos(start);
            var rb = gameObject.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            col = gameObject.AddComponent<SphereCollider>();
            col.isTrigger = false;
            col.radius = size * 0.45f;

            AddBlock(transform, 1f, "Head");
            foreach (var s in SegmentScale)
            {
                var seg = AddBlock(chunk.transform, s, "Segment");
                seg.position = FloorPoint(transform.position, s);
                body.Add(seg);
            }
            PickNext();
        }

        Transform AddBlock(Transform parent, float scale, string blockName)
        {
            var mesh = Resources.Load<Mesh>("Slock/SlockJellyLow") ?? Resources.Load<Mesh>("Slock/SlockJelly");
            var go = new GameObject(blockName);
            go.transform.SetParent(parent, false);
            go.transform.localScale = new Vector3(size, height, size) * scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = Visuals.WormJelly;
            go.AddComponent<JellyWobble>();
            jellies.Add(r);
            allRenderers.Add(r);
            return go.transform;
        }

        /// <summary>Centre of a block of relative <paramref name="scale"/> resting on the floor at <paramref name="p"/>'s x/z.</summary>
        Vector3 FloorPoint(Vector3 p, float scale) => new(p.x, chunk.FloorY + height * scale * 0.5f, p.z);

        Vector3 Pos(Vector2Int cell) => chunk.TileCenter(cell.x, cell.y) + Vector3.up * height * 0.5f;

        /// <summary>Eaten during power mode: vanish, then crawl back out from home later.</summary>
        public void GetEaten(float respawnDelay)
        {
            eaten = true;
            respawnAt = Time.time + respawnDelay;
            col.enabled = false;
            foreach (var r in allRenderers) r.enabled = false;
        }

        void Respawn()
        {
            eaten = false;
            stolenTime = 0f;
            from = to = home;
            t = 0f;
            transform.position = Pos(home);
            for (int i = 0; i < body.Count; i++) body[i].position = FloorPoint(transform.position, SegmentScale[i]);
            col.enabled = true;
            foreach (var r in allRenderers) r.enabled = true;
            look = -1; // force UpdateLook to re-pick material + solidity on the next frame
            PickNext();
        }

        void UpdateLook()
        {
            var gm = GameManager.I;
            int want = 0;
            if (gm != null && gm.PowerActive)
                want = gm.PowerRemaining < 2f && Mathf.Repeat(Time.time, 0.3f) < 0.15f ? 2 : 1;
            if (want == look) return;
            look = want;
            var mat = want switch { 1 => Visuals.WormScared, 2 => Visuals.WormFlash, _ => Visuals.WormJelly };
            foreach (var r in jellies) r.sharedMaterial = mat;
            // Edible (power mode): soft trigger so the slock passes in and eats it.
            // Otherwise: solid jelly that the slock collides with and bounces off.
            if (col != null && !eaten) col.isTrigger = want > 0;
        }

        void PickNext()
        {
            options.Clear();
            var back = from;
            foreach (var d in new[] { Vector2Int.up, Vector2Int.down, Vector2Int.left, Vector2Int.right })
            {
                var n = to + d;
                if (chunk.IsCrawlable(n.x, n.y) && n != back) options.Add(n);
            }
            from = to;
            to = options.Count > 0 ? options[rng.Next(options.Count)] : back; // dead end: turn around
        }

        void Update()
        {
            if (chunk == null || chunk.Tiles == null) return; // e.g. after a live script reload
            if (eaten)
            {
                if (Time.time >= respawnAt) Respawn();
                else return;
            }
            UpdateLook();

            // Head: slide one block (eased), pause, repeat. Frightened worms are slow.
            t += Time.deltaTime / stepTime * (look > 0 ? 0.55f : 1f);
            if (t >= 1f) { t -= 1f; PickNext(); }
            float m = Mathf.Clamp01(t / MoveShare);
            m = m * m * (3f - 2f * m);
            transform.position = Vector3.Lerp(Pos(from), Pos(to), m);

            // Body: each block eases toward the one ahead, so the worm stretches out while the head moves
            // and telescopes back in (the small blocks tucking inside the head) while it pauses.
            float k = 1f - Mathf.Exp(-CatchUp * Time.deltaTime);
            var lead = transform.position;
            for (int i = 0; i < body.Count; i++)
            {
                var seg = body[i];
                var target = FloorPoint(lead, SegmentScale[i]);
                seg.position = Vector3.Lerp(seg.position, target, k);
                lead = seg.position;
            }
        }

        void OnTriggerEnter(Collider other)
        {
            var slock = other.GetComponentInParent<SlockController>();
            if (slock != null) GameManager.I?.OnWormHit(this, slock);
        }

        void OnCollisionEnter(Collision other)
        {
            var slock = other.collider.GetComponentInParent<SlockController>();
            if (slock != null) GameManager.I?.OnWormHit(this, slock);
        }
    }
}
