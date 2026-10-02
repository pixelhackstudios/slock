using System.Collections.Generic;
using UnityEngine;

namespace Slock
{
    /// <summary>
    /// A slorm: a green block worm that inches through the maze like a telescope. The head, one tile cube, slides two
    /// tiles while the body stays put; then it stops and the five segments (each 20% smaller than the one ahead)
    /// follow in a short train until they are all tucked inside the head, and it slides again. Nothing rotates:
    /// the blocks stay square to the grid. The head is a trigger, never a physical pusher (a kinematic block would
    /// shove the slock through walls): touching it knocks the slock and the slorm about 3 tiles apart and costs time,
    /// unless a power gem is active, in which case it gets eaten.
    /// </summary>
    public class Worm : MonoBehaviour
    {
        static readonly float[] SegmentScale = { 0.8f, 0.64f, 0.512f, 0.41f, 0.328f }; // each 20% smaller than the one ahead
        const int SlideTiles = 2;          // the head slides two tiles per move (one where two won't fit)
        const float SegmentGap = 0.08f;    // edge-to-edge gap between segments in the train, in tiles
        const float KnockSpeed = 2.5f;     // a knock-back slide runs this many times faster than crawling

        MazeChunk chunk;
        Vector2Int from, to, home;
        float t, tilesPerSecond, size, height;
        bool sliding;                       // head moving; otherwise the body is catching up
        bool knocked;                       // this slide is a knock-back from hitting the slock
        Vector3 slideStart;                 // where the head's current slide began (mid-tile after a knock)
        float gatherTime;
        readonly List<Vector3> gatherFrom = new();
        System.Random rng;
        readonly List<Transform> body = new();
        readonly List<MeshRenderer> jellies = new();
        readonly List<Renderer> allRenderers = new();
        readonly List<Vector2Int> options = new(4);
        bool eaten;
        float respawnAt;
        float releaseAt = float.MaxValue;   // waits at home in the pen until its section releases it
        int look = -1;
        BoxCollider col;

        public bool Eaten => eaten;
        /// <summary>Total time this slorm has taken from the player and still owes back on being eaten.</summary>
        public float stolenTime;

        public void Init(MazeChunk c, Vector2Int start, float tilesPerSecond, int seed)
        {
            chunk = c;
            size = c.TileSize;
            height = size;                // a one-tile cube
            this.tilesPerSecond = tilesPerSecond;
            from = to = home = start;
            rng = new System.Random(seed);

            // Physics lives on the root (kinematic body that moves with the head): a trigger only, so it never
            // pushes the slock; hits are handled by GameManager.OnWormHit.
            transform.position = Pos(start);
            var rb = gameObject.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            col = gameObject.AddComponent<BoxCollider>();
            col.isTrigger = true;
            col.size = Vector3.one * size * 0.9f;

            AddBlock(transform, 1f, "Head", wobble: false); // stays an exact one-tile cube
            foreach (var s in SegmentScale)
            {
                var seg = AddBlock(chunk.transform, s, "Segment");
                seg.position = FloorPoint(transform.position, s);
                body.Add(seg);
            }
            PickNext();
        }

        Transform AddBlock(Transform parent, float scale, string blockName, bool wobble = true)
        {
            var mesh = Resources.Load<Mesh>("Slock/SlockJellyLow") ?? Resources.Load<Mesh>("Slock/SlockJelly");
            var go = new GameObject(blockName);
            go.transform.SetParent(parent, false);
            go.transform.localScale = new Vector3(size, height, size) * scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = Visuals.WormJelly;
            if (wobble) go.AddComponent<JellyWobble>(); // squash/sway would bend the head off the tile size
            jellies.Add(r);
            allRenderers.Add(r);
            return go.transform;
        }

        /// <summary>Centre of a block of relative <paramref name="scale"/> resting on the floor at <paramref name="p"/>'s x/z.</summary>
        Vector3 FloorPoint(Vector3 p, float scale) => new(p.x, chunk.FloorY + height * scale * 0.5f, p.z);

        Vector3 Pos(Vector2Int cell) => chunk.TileCenter(cell.x, cell.y) + Vector3.up * height * 0.5f;

        /// <summary>Leave the pen at <paramref name="time"/> (until then it sits at home).</summary>
        public void ReleaseAt(float time) => releaseAt = time;

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
        }

        /// <summary>Start the next slide from <see cref="to"/>: two tiles straight on if it can, else one, never
        /// straight back the way it came unless it's a dead end.</summary>
        void PickNext()
        {
            var back = from - to;
            if (back != Vector2Int.zero) back = new Vector2Int(System.Math.Sign(back.x), System.Math.Sign(back.y));
            from = to;
            to = Choose(SlideTiles, back) ?? Choose(1, back) ?? from + (back == Vector2Int.zero ? Vector2Int.zero : back);
            slideStart = Pos(from);
            t = 0f;
            sliding = true;
            knocked = false;
        }

        /// <summary>Hit the slock: get knocked up to <paramref name="tiles"/> blocks straight away from
        /// <paramref name="slockPos"/> (as far as open floor allows; sideways if straight back is blocked), quickly,
        /// then carry on crawling (not back toward it).</summary>
        public void KnockBack(Vector3 slockPos, int tiles = 3)
        {
            if (eaten || chunk == null) return;
            var away = transform.position - slockPos;
            var dir = Mathf.Abs(away.x) >= Mathf.Abs(away.z)
                ? new Vector2Int(away.x >= 0f ? 1 : -1, 0)
                : new Vector2Int(0, away.z >= 0f ? 1 : -1);
            // The block the head is mostly over right now.
            var at = !sliding || t >= 0.5f ? to : from;
            // Straight away if there's room; otherwise (e.g. just round a corner) sideways, whichever side is longer.
            int Room(Vector2Int d)
            {
                int k = 0;
                while (k < tiles && chunk.IsCrawlable(at.x + d.x * (k + 1), at.y + d.y * (k + 1))) k++;
                return k;
            }
            int n = Room(dir);
            if (n == 0)
            {
                var side = new Vector2Int(dir.y, dir.x);
                int a = Room(side), b = Room(-side);
                if (a > 0 || b > 0) { dir = a >= b ? side : -side; n = Mathf.Max(a, b); }
            }
            slideStart = transform.position;
            from = at;
            to = at + dir * n;
            t = 0f;
            sliding = true;
            knocked = true;
            releaseAt = Mathf.Min(releaseAt, Time.time); // knocked out of the pen early: it's loose now
        }

        Vector2Int? Choose(int tiles, Vector2Int back)
        {
            options.Clear();
            foreach (var d in new[] { Vector2Int.up, Vector2Int.down, Vector2Int.left, Vector2Int.right })
            {
                if (d == back) continue;
                bool clear = true;
                for (int i = 1; i <= tiles && clear; i++)
                    clear = chunk.IsCrawlable(from.x + d.x * i, from.y + d.y * i);
                if (clear) options.Add(from + d * tiles);
            }
            return options.Count > 0 ? options[rng.Next(options.Count)] : null;
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
            if (Time.time < releaseAt) return; // still waiting in the pen

            float speed = tilesPerSecond * (look > 0 ? 0.55f : 1f); // frightened slorms are slow
            if (sliding)
            {
                // Head: one eased slide; the body stays where it was.
                var end = Pos(to);
                float tiles = Mathf.Max(1f, Vector3.Distance(slideStart, end) / size);
                t = Mathf.Min(1f, t + Time.deltaTime * speed * (knocked ? KnockSpeed : 1f) / tiles);
                float m = knocked ? 1f - (1f - t) * (1f - t) : t * t * (3f - 2f * t); // a knock starts fast and eases out
                transform.position = Vector3.Lerp(slideStart, end, m);
                if (t < 1f) return;
                sliding = false;
                gatherTime = 0f;
                gatherFrom.Clear();
                foreach (var seg in body) gatherFrom.Add(seg.position);
                return;
            }

            // Body: each segment sets off once the one ahead is a block-edge gap clear of it, so the train is
            // evenly spaced edge to edge (smaller blocks sit closer, centre to centre), and slides into the head.
            gatherTime += Time.deltaTime;
            bool gathered = true;
            float lag = 0f;
            for (int i = 0; i < body.Count; i++)
            {
                if (i > 0) lag += size * ((SegmentScale[i - 1] + SegmentScale[i]) * 0.5f + SegmentGap);
                var target = FloorPoint(transform.position, SegmentScale[i]);
                float dist = Vector3.Distance(gatherFrom[i], target);
                float travelled = Mathf.Max(0f, gatherTime * speed * size - lag);
                float f = dist < 1e-4f ? 1f : Mathf.Clamp01(travelled / dist);
                body[i].position = Vector3.Lerp(gatherFrom[i], target, f);
                if (f < 1f) gathered = false;
            }
            if (gathered) PickNext();
        }

        void OnTriggerEnter(Collider other)
        {
            var slock = other.GetComponentInParent<SlockController>();
            if (slock != null) GameManager.I?.OnWormHit(this, slock);
        }

        // Still overlapping (e.g. inside the hit cooldown): keep them pushed apart so the slock can't slip through.
        void OnTriggerStay(Collider other)
        {
            var slock = other.GetComponentInParent<SlockController>();
            if (slock != null) GameManager.I?.OnWormHit(this, slock);
        }
    }
}
