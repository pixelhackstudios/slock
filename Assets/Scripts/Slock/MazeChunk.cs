using System.Collections.Generic;
using UnityEngine;

namespace Slock
{
    public enum Tile : byte { Void, Floor, Wall }

    /// <summary>
    /// One procedurally generated section of the endless course: an entry ramp climbing from the previous
    /// chunk's height, then a W x L tile maze with rooms, pits, open edges, pellets, gems and worms.
    /// Chunks are laid end to end along +Z, each one <see cref="Rise"/> higher than the last.
    ///
    /// At the centre sits a slorm pen (Pac-Man style): a small wall ring with one opening. Slorms start
    /// inside it and crawl out; it holds no pellets or pickups.
    ///
    /// "Resolution" climbs as you go: every gate shrinks the block size by <see cref="BlockStep"/> (60 -> 58 -> 56 ...),
    /// while a section keeps roughly the same footprint, so each section has more, smaller cells than the last.
    ///
    /// Side rooms hang off a section at a lower level: one off the maze's left edge, reached by a ramp
    /// you slide down, which boosts you back up.
    /// Their pellets count toward opening the gate; they also hold a power gem and either a big clock or a gate key.
    ///
    /// The entry climb ramp past each gate is deliberately room-free and smooth: a single slope with a small
    /// booster so the slock can always make the Rise to the next section.
    ///
    /// Positions use "keys": (ix, k) where world x = ix * TileSize and world z = Z0 + k * TileSize.
    /// The ramp occupies rows k = 0..RampTiles-1, the main maze rows k = RampTiles..RampTiles+L-1.
    /// </summary>
    public class MazeChunk : MonoBehaviour
    {
        public const int BaseBlock = 60, BlockStep = 2, MinBlock = 20;
        const float BaseWidth = 18f, BaseLength = 18f, RampLength = 6f;
        public const float Rise = 1.0f;
        const float SideDrop = 3f;       // how far below its entrance a side room sits
        const int LaunchTiles = 4;       // a ramp boost launches the slock onto this block past the top

        /// <summary>Block size of section <paramref name="index"/> in "resolution units" (60 at the start).</summary>
        public static int BlockOf(int index) => Mathf.Max(MinBlock, BaseBlock - BlockStep * Mathf.Max(0, index));
        /// <summary>World size of one grid block (and of the slock) in section <paramref name="index"/>.</summary>
        public static float TileSizeOf(int index) => BlockOf(index) / (float)BaseBlock;
        static int Odd(float v) { int n = Mathf.RoundToInt(v); return n % 2 == 0 ? n + 1 : n; }
        // Maze cells sit on odd columns counted from the centre, so the centre column index must itself be odd
        // (width 15, 19, 23 ...). Otherwise every other column is off by one and an extra, hidden wall column
        // lines the maze's inside edges, blocking the side-room openings.
        static int WOf(int i)
        {
            int w = Odd(BaseWidth / TileSizeOf(i));
            return (w / 2) % 2 == 1 ? w : w + 2;
        }
        static int LOf(int i) => Odd(BaseLength / TileSizeOf(i));
        static int RampOf(int i) => Mathf.Max(4, Mathf.RoundToInt(RampLength / TileSizeOf(i)));
        static float LengthOf(int i) => (RampOf(i) + LOf(i)) * TileSizeOf(i);

        // Where each section's ramp begins along Z (cumulative, since sections differ in length).
        static readonly List<float> startEdges = new() { -0.5f }; // section 0: half its (size 1) first tile
        static float StartEdgeOf(int i)
        {
            while (startEdges.Count <= i) startEdges.Add(startEdges[^1] + LengthOf(startEdges.Count - 1));
            return startEdges[i];
        }

        public static float FloorYOf(int index) => Mathf.Max(0, index) * Rise;
        public static float StartZOf(int index) => StartEdgeOf(Mathf.Max(0, index)) + TileSizeOf(index) * 0.5f;
        public static int IndexAt(float z)
        {
            int i = 0;
            while (z >= StartEdgeOf(i + 1)) i++;
            return i;
        }

        // Per-section grid dimensions.
        public int W { get; private set; }         // odd, so the centre column is a maze cell
        public int L { get; private set; }         // odd
        public int RampTiles { get; private set; }
        public float TileSize { get; private set; }
        public float WallHeight => TileSize;       // blocks are cubes
        public int Center => W / 2;

        public int Index { get; private set; }
        public float FloorY { get; private set; }
        public float Z0 { get; private set; }
        public Tile[,] Tiles { get; private set; }
        float[,] mainDepth;

        /// <summary>Pellets still uneaten in this section (main maze + side rooms); the gate opens at 0.</summary>
        public int PelletsLeft => pellets.Count;
        public bool GateOpen => gate == null;

        class Pellet { public GameObject go; public bool gold; }
        readonly Dictionary<Vector2Int, Pellet> pellets = new();
        readonly HashSet<Vector2Int> reserved = new();     // keys holding a pickup: no pellet there
        readonly HashSet<Vector2Int> penCells = new();     // slorm-pen floor (maze-local): no pellets or pickups
        readonly List<Vector2Int> penHomes = new();        // slorm starting blocks inside the pen (maze-local)
        int penX0, penZ0, penX1, penZ1;                    // pen bounds (maze-local, inclusive)
        struct Floater { public Transform t; public Vector3 home; public float phase, spin, bob; }
        readonly List<Floater> floaters = new();
        GameObject gate;
        GameObject checkpoint;
        bool exitSealed;
        int edgeRoomRow = -1;                              // main-maze row of the side room's doorway in the left wall

        /// <summary>A lower bonus area: its own tile grid, mirrored to the left (sign -1) or right (sign +1).</summary>
        class SideRoom
        {
            public Tile[,] t;
            public float[,] depth;
            public int sign, ix0, k0, entrance;    // near edge at |ix| = ix0; entrance at local (0, entrance)
            public float floorY;
            public Vector2Int Key(int lx, int lz) => new(sign * (ix0 + lx), k0 + lz);
        }
        readonly List<SideRoom> rooms = new();
        readonly List<Worm> slorms = new();

        public Vector2Int KeyAt(Vector3 world) =>
            new(Mathf.RoundToInt(world.x / TileSize), Mathf.RoundToInt((world.z - Z0) / TileSize));
        Vector3 KeyCenter(Vector2Int key, float y) => new(key.x * TileSize, y, Z0 + key.y * TileSize);
        Vector2Int MainKey(int tx, int tz) => new(tx - Center, RampTiles + tz);

        public Vector3 TileCenter(int tx, int tz) => KeyCenter(MainKey(tx, tz), FloorY);

        public bool InBounds(int x, int z) => x >= 0 && x < W && z >= 0 && z < L;
        public bool IsFloor(int x, int z) => InBounds(x, z) && Tiles[x, z] == Tile.Floor;

        /// <summary>Tiles worms may crawl on: floor away from the open outer edge and the entry/exit corridors.</summary>
        public bool IsCrawlable(int x, int z) => IsFloor(x, z) && x > 0 && x < W - 1 && z > 0 && z < L - 1;

        // ------------------------------------------------------------------ creation

        public static MazeChunk Create(int index, int seed, Transform parent)
        {
            var go = new GameObject($"Chunk {index}");
            go.transform.SetParent(parent, false);
            var chunk = go.AddComponent<MazeChunk>();
            chunk.Generate(index, seed);
            return chunk;
        }

        void Generate(int index, int seed)
        {
            Index = index;
            TileSize = TileSizeOf(index);
            W = WOf(index);
            L = LOf(index);
            RampTiles = RampOf(index);
            FloorY = FloorYOf(index);
            Z0 = StartZOf(index);
            var rng = new System.Random(seed * 7919 + index * 104729);
            var d = Difficulty.For(index);

            Tiles = GenerateLayout(rng, d, out var depth);
            mainDepth = depth;

            var mb = new MeshBuilder(TileSize, Z0, FloorY);
            if (rng.NextDouble() < d.EdgeRoomChance) BuildEdgeRoom(mb, rng, d);
            AddTiles(mb, Tiles, depth, FloorY, MainKey, 1);
            BuildClimbRamp(mb);
            FinishMesh(mb);

            SpawnCheckpoint();
            SpawnPickups(rng, d);
            foreach (var r in rooms) SpawnRoomRewards(r, rng);
            SpawnPowerups(rng);
            SpawnPellets();
            SpawnWorms(rng, d);
        }

        // ------------------------------------------------------------------ layout

        Tile[,] GenerateLayout(System.Random rng, Difficulty d, out float[,] depth)
        {
            var t = CarveMaze(W, L, new Vector2Int(Center, 1), d.LoopChance, rng);

            // Entry and exit corridors.
            t[Center, 0] = Tile.Floor;
            t[Center, L - 1] = Tile.Floor;

            // Open rooms, optionally with pits and a missing outer wall.
            var pits = new List<Vector2Int>();
            float areaScale = W * L / (BaseWidth * BaseLength);
            int roomCount = Mathf.RoundToInt(rng.Next(d.MinRooms, d.MaxRooms + 1) * areaScale);
            for (int r = 0; r < roomCount; r++)
            {
                int rw = rng.Next(3, 6), rl = rng.Next(3, 6);
                int rx = rng.Next(1, W - rw);
                if (rng.NextDouble() < 0.45) rx = rng.Next(2) == 0 ? 1 : W - 1 - rw; // hug an edge
                int rz = rng.Next(2, L - 1 - rl);
                for (int x = rx; x < rx + rw; x++)
                for (int z = rz; z < rz + rl; z++)
                {
                    bool interior = x > rx && x < rx + rw - 1 && z > rz && z < rz + rl - 1;
                    if (interior && rng.NextDouble() < d.PitChance) { t[x, z] = Tile.Void; pits.Add(new(x, z)); }
                    else t[x, z] = Tile.Floor;
                }

                if (rng.NextDouble() < d.OpenEdgeChance)
                {
                    if (rx == 1) for (int z = rz; z < rz + rl; z++) t[0, z] = Tile.Floor;
                    if (rx + rw == W - 1) for (int z = rz; z < rz + rl; z++) t[W - 1, z] = Tile.Floor;
                }
            }

            // A clear corridor runs all the way round just inside the outer wall (main maze only, not side rooms).
            for (int x = 1; x < W - 1; x++) t[x, 1] = t[x, L - 2] = Tile.Floor;
            for (int z = 1; z < L - 1; z++) t[1, z] = t[W - 2, z] = Tile.Floor;

            // Slorm pen at the centre (Pac-Man style): walls with one opening, slorms start inside.
            CarveSlormPen(t);

            // Guarantee the exit is reachable; if pits cut the path, fill them in.
            if (DistanceMap(t, new(Center, 0))[Center, L - 1] < 0)
                foreach (var p in pits) t[p.x, p.y] = Tile.Floor;
            // If the pen itself cut the only path, open it up rather than trap the player.
            if (DistanceMap(t, new(Center, 0))[Center, L - 1] < 0)
                ClearSlormPen(t);

            // The climb ramp launches the slock onto the 4th block in: that one is always open floor.
            t[Center, LaunchTiles - 1] = Tile.Floor;

            depth = EdgeDepths(t, rng, 0, W - 1);
            return t;
        }

        /// <summary>Centre pen the slorms start in: a 6x4 wall ring (maze-local) with one opening toward the exit and a
        /// 4x2 floor inside, standing clear in a one-block empty corridor all the way round (so it always reads as a
        /// rectangle, and any maze corridor it cuts still connects via that ring). Registers <see cref="penCells"/>
        /// (no pellets or pickups there) and <see cref="penHomes"/> (slorm starting blocks).</summary>
        void CarveSlormPen(Tile[,] t)
        {
            penCells.Clear();
            penHomes.Clear();
            int cx = Center;
            int cz = L / 2;
            if (cz % 2 == 0) cz++; // sit on a maze-cell row
            int x0 = cx - 2, x1 = cx + 3, z0 = cz - 1, z1 = cz + 2;   // 4x2 = 8 open blocks inside, opening at cx
            if (x0 - 1 < 1 || x1 + 1 > W - 2 || z0 - 1 < 2 || z1 + 1 > L - 2) return; // too small: skip the pen
            penX0 = x0 - 1; penZ0 = z0 - 1; penX1 = x1 + 1; penZ1 = z1 + 1;
            for (int x = penX0; x <= penX1; x++)
            for (int z = penZ0; z <= penZ1; z++)
            {
                bool ring = x == penX0 || x == penX1 || z == penZ0 || z == penZ1;
                bool edge = x == x0 || x == x1 || z == z0 || z == z1;
                bool opening = x == cx && z == z1;
                t[x, z] = ring || !edge || opening ? Tile.Floor : Tile.Wall;
            }
            for (int x = x0 + 1; x <= x1 - 1; x++)
            for (int z = z0 + 1; z <= z1 - 1; z++)
            {
                penCells.Add(new(x, z));
                penHomes.Add(new(x, z));
            }
            penCells.Add(new(cx, z1));
        }

        /// <summary>Fallback when the pen blocks the only entry-to-exit path: flatten it to open floor.</summary>
        void ClearSlormPen(Tile[,] t)
        {
            for (int x = penX0; x <= penX1; x++)
            for (int z = penZ0; z <= penZ1; z++)
                t[x, z] = Tile.Floor;
            penCells.Clear();
            penHomes.Clear();
        }

        /// <summary>Perfect maze (recursive backtracker on odd cells) from <paramref name="start"/>, plus some loops.</summary>
        static Tile[,] CarveMaze(int w, int l, Vector2Int start, float loopChance, System.Random rng)
        {
            var t = new Tile[w, l];
            for (int x = 0; x < w; x++)
            for (int z = 0; z < l; z++)
                t[x, z] = Tile.Wall;

            var stack = new Stack<Vector2Int>();
            t[start.x, start.y] = Tile.Floor;
            stack.Push(start);
            var options = new List<Vector2Int>(4);
            while (stack.Count > 0)
            {
                var cur = stack.Peek();
                options.Clear();
                foreach (var dir in Dirs)
                {
                    var n = cur + dir * 2;
                    if (n.x >= 1 && n.x <= w - 2 && n.y >= 1 && n.y <= l - 2 && t[n.x, n.y] == Tile.Wall)
                        options.Add(dir);
                }
                if (options.Count == 0) { stack.Pop(); continue; }
                var pick = options[rng.Next(options.Count)];
                var mid = cur + pick;
                var next = cur + pick * 2;
                t[mid.x, mid.y] = Tile.Floor;
                t[next.x, next.y] = Tile.Floor;
                stack.Push(next);
            }

            // Knock out extra walls so there are loops (more ways to recover from a bad slide).
            for (int x = 1; x < w - 1; x++)
            for (int z = 1; z < l - 1; z++)
            {
                if (t[x, z] != Tile.Wall || rng.NextDouble() > loopChance) continue;
                bool horiz = x % 2 == 0 && z % 2 == 1 && t[x - 1, z] == Tile.Floor && t[x + 1, z] == Tile.Floor;
                bool vert = x % 2 == 1 && z % 2 == 0 && t[x, z - 1] == Tile.Floor && t[x, z + 1] == Tile.Floor;
                if (horiz || vert) t[x, z] = Tile.Floor;
            }
            return t;
        }

        /// <summary>Column depth under each tile: deep ragged pillars along the given edge columns, like the reference art.</summary>
        static float[,] EdgeDepths(Tile[,] t, System.Random rng, int edgeA, int edgeB)
        {
            int w = t.GetLength(0), l = t.GetLength(1);
            var depth = new float[w, l];
            for (int x = 0; x < w; x++)
            for (int z = 0; z < l; z++)
                depth[x, z] = x == edgeA || x == edgeB ? 3f + (float)rng.NextDouble() * 7f : 3f;
            return depth;
        }

        static readonly Vector2Int[] Dirs = { Vector2Int.up, Vector2Int.down, Vector2Int.left, Vector2Int.right };

        /// <summary>Walking distance (in tiles) from <paramref name="from"/> over floor; -1 where unreachable.</summary>
        static int[,] DistanceMap(Tile[,] t, Vector2Int from)
        {
            int w = t.GetLength(0), l = t.GetLength(1);
            var dist = new int[w, l];
            for (int x = 0; x < w; x++)
            for (int z = 0; z < l; z++)
                dist[x, z] = -1;
            var q = new Queue<Vector2Int>();
            q.Enqueue(from);
            dist[from.x, from.y] = 0;
            while (q.Count > 0)
            {
                var c = q.Dequeue();
                foreach (var dir in Dirs)
                {
                    var n = c + dir;
                    if (n.x < 0 || n.x >= w || n.y < 0 || n.y >= l || dist[n.x, n.y] >= 0 || t[n.x, n.y] != Tile.Floor) continue;
                    dist[n.x, n.y] = dist[c.x, c.y] + 1;
                    q.Enqueue(n);
                }
            }
            return dist;
        }

        // ------------------------------------------------------------------ side rooms

        /// <summary>Side room layout: a loopy mini-maze entered at local (0, entrance), with holes and open far edges.</summary>
        SideRoom MakeRoom(System.Random rng, Difficulty d, int sign, int ix0, int k0, int w, int l, int entrance, float floorY)
        {
            var t = CarveMaze(w, l, new Vector2Int(1, entrance), 0.35f, rng);
            t[0, entrance] = Tile.Floor;

            // Holes, but never ones that cut part of the room off.
            int reachable = Count(DistanceMap(t, new(0, entrance)));
            for (int tries = 0; tries < w * l / 6; tries++)
            {
                int x = rng.Next(2, w - 1), z = rng.Next(1, l - 1);
                if (t[x, z] != Tile.Floor || rng.NextDouble() > d.PitChance) continue;
                t[x, z] = Tile.Void;
                int now = Count(DistanceMap(t, new(0, entrance)));
                if (now < reachable - 1) t[x, z] = Tile.Floor;
                else reachable = now;
            }

            // Missing far wall here and there: slide too far and you're off the edge.
            for (int z = 1; z < l - 1; z++)
                if (t[w - 2, z] == Tile.Floor && rng.NextDouble() < d.OpenEdgeChance * 0.5)
                    t[w - 1, z] = Tile.Floor;

            var room = new SideRoom { t = t, sign = sign, ix0 = ix0, k0 = k0, entrance = entrance, floorY = floorY };
            room.depth = EdgeDepths(t, rng, w - 1, -1);
            rooms.Add(room);
            return room;
        }

        static int Count(int[,] dist)
        {
            int n = 0;
            foreach (var v in dist) if (v >= 0) n++;
            return n;
        }

        /// <summary>A side room off the main maze's left edge, down a ramp.</summary>
        void BuildEdgeRoom(MeshBuilder mb, System.Random rng, Difficulty d)
        {
            int rampLen = Mathf.Max(3, Mathf.RoundToInt(4f / TileSize));
            int w = Odd(rng.Next(7, 10) / TileSize), l = Odd(rng.Next(7, 10) / TileSize);
            int k0 = RampTiles + 2 * rng.Next(0, (L - l) / 2 + 1);   // keep row parity aligned with maze cells
            int entrance = 1 + 2 * rng.Next(0, (l - 1) / 2);         // odd, 1..l-2
            int tz = k0 + entrance - RampTiles;                        // main maze row of the opening (odd)
            // Doorway, and the 4th block in where the ramp's launch lands: always open floor.
            Tiles[0, tz] = Tile.Floor;
            Tiles[LaunchTiles - 1, tz] = Tile.Floor;
            edgeRoomRow = tz;

            float top = FloorY, bottom = FloorY - SideDrop;
            float xNear = -(Center + 0.5f) * TileSize, xFar = xNear - rampLen * TileSize;
            var room = MakeRoom(rng, d, -1, Center + rampLen + 1, k0, w, l, entrance, bottom);
            var boost = AddSideRamp(mb, xFar, xNear, bottom, top, RampTiles + tz, +1f);
            boost.top = new Vector3(xNear, top, 0f);
            boost.landing = TileCenter(LaunchTiles - 1, tz);
            boost.hop = WallHeight;
            boost.downStop = KeyCenter(room.Key(1, entrance), bottom); // the room's second block
            AddTiles(mb, room.t, room.depth, room.floorY, room.Key, -1);
        }

        /// <summary>
        /// A one-block-wide ramp running along X between <paramref name="x0"/> (height y0) and <paramref name="x1"/> (y1),
        /// on grid row <paramref name="k"/>, with walls either side and a booster that launches the slock toward the top.
        /// </summary>
        BoostRamp AddSideRamp(MeshBuilder mb, float x0, float x1, float y0, float y1, int k, float upSign)
        {
            AddSideRampGeometry(mb, x0, x1, y0, y1, k);
            return SpawnSideBoost(x0, x1, y0, y1, k, upSign);
        }

        /// <summary>Side-ramp prisms only (no booster objects), so the mesh can be rebuilt after a wall breach.</summary>
        void AddSideRampGeometry(MeshBuilder mb, float x0, float x1, float y0, float y1, int k)
        {
            float z = Z0 + k * TileSize, h = TileSize * 0.5f;
            float bot = Mathf.Min(y0, y1) - 3f;
            mb.PrismX(x0, x1, z - h, z + h, bot, y0, bot, y1, MeshBuilder.Faces.All, MeshBuilder.RampSub);
            mb.PrismX(x0, x1, z - 3 * h, z - h, bot, y0 + WallHeight, bot, y1 + WallHeight, MeshBuilder.Faces.All, MeshBuilder.WallTopSub);
            mb.PrismX(x0, x1, z + h, z + 3 * h, bot, y0 + WallHeight, bot, y1 + WallHeight, MeshBuilder.Faces.All, MeshBuilder.WallTopSub);
        }

        /// <summary>Side-ramp booster trigger + chevrons.</summary>
        BoostRamp SpawnSideBoost(float x0, float x1, float y0, float y1, int k, float upSign)
        {
            float z = Z0 + k * TileSize;
            // Booster: a trigger over the ramp plus glowing chevrons pointing uphill.
            var go = new GameObject("Boost Ramp");
            go.transform.SetParent(transform, false);
            go.transform.position = new Vector3((x0 + x1) * 0.5f, (y0 + y1) * 0.5f + TileSize, z);
            var box = go.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = new Vector3(Mathf.Abs(x1 - x0) + TileSize, Mathf.Abs(y1 - y0) + TileSize * 2f, TileSize * 0.9f);
            var boost = go.AddComponent<BoostRamp>();
            boost.up = new Vector3(upSign, 0f, 0f);

            float slope = Mathf.Atan2(y1 - y0, x1 - x0) * Mathf.Rad2Deg;
            int chevrons = Mathf.Max(2, Mathf.RoundToInt(Mathf.Abs(x1 - x0) / (TileSize * 1.5f)));
            for (int i = 0; i < chevrons; i++)
            {
                float f = (i + 0.5f) / chevrons;
                var p = new Vector3(Mathf.Lerp(x0, x1, f), Mathf.Lerp(y0, y1, f) + 0.06f * TileSize, z);
                for (int side = -1; side <= 1; side += 2)
                {
                    var bar = Decor(PrimitiveType.Cube, go.transform, Vector3.zero, new Vector3(TileSize * 0.12f, 0.04f * TileSize, TileSize * 0.45f), Visuals.Boost);
                    bar.transform.position = p + new Vector3(0, 0, side * TileSize * 0.17f);
                    bar.transform.rotation = Quaternion.Euler(0, side * upSign * -35f, slope);
                }
            }
            return boost;
        }

        // ------------------------------------------------------------------ mesh

        void AddTiles(MeshBuilder mb, Tile[,] t, float[,] depth, float floorY, System.Func<int, int, Vector2Int> key, int xSign)
        {
            int w = t.GetLength(0), l = t.GetLength(1);
            float h = TileSize * 0.5f, wallH = WallHeight;
            float TopOf(int x, int z) => floorY + (t[x, z] == Tile.Wall ? wallH : 0f);
            bool Hides(int nx, int nz, float top, float bot)
            {
                if (nx < 0 || nx >= w || nz < 0 || nz >= l || t[nx, nz] == Tile.Void) return false;
                return TopOf(nx, nz) >= top && floorY - depth[nx, nz] <= bot;
            }

            for (int x = 0; x < w; x++)
            for (int z = 0; z < l; z++)
            {
                if (t[x, z] == Tile.Void) continue;
                float top = TopOf(x, z), bot = floorY - depth[x, z];
                var faces = MeshBuilder.Faces.Top;
                if (!Hides(x + xSign, z, top, bot)) faces |= MeshBuilder.Faces.PosX;
                if (!Hides(x - xSign, z, top, bot)) faces |= MeshBuilder.Faces.NegX;
                if (!Hides(x, z + 1, top, bot)) faces |= MeshBuilder.Faces.PosZ;
                if (!Hides(x, z - 1, top, bot)) faces |= MeshBuilder.Faces.NegZ;
                var c = KeyCenter(key(x, z), floorY);
                mb.Prism(c.x - h, c.x + h, c.z - h, c.z + h, bot, top, bot, top, faces,
                    t[x, z] == Tile.Wall ? MeshBuilder.WallTopSub : MeshBuilder.TopSub);
            }
        }

        /// <summary>The one-block corridor climbing from the previous section: one smooth slope with a small
        /// booster so the slock always makes the Rise. No side rooms leave this ramp (it sits past the gate).</summary>
        void BuildClimbRamp(MeshBuilder mb)
        {
            BuildClimbRampGeometry(mb);
            SpawnClimbBoost();
        }

        /// <summary>Climb-ramp prisms only (no booster objects), so the mesh can be rebuilt after a wall breach.</summary>
        void BuildClimbRampGeometry(MeshBuilder mb)
        {
            float h = TileSize * 0.5f;
            float prevY = FloorYOf(Index - 1);
            float zA = Z0 - h, zB = Z0 + (RampTiles - 0.5f) * TileSize;
            float bot = Mathf.Min(prevY, FloorY) - 3f;
            var all = MeshBuilder.Faces.All;

            mb.Prism(-h, h, zA, zB, bot, prevY, bot, FloorY, all, MeshBuilder.RampSub);
            mb.Prism(-3 * h, -h, zA, zB, bot, prevY + WallHeight, bot, FloorY + WallHeight, all, MeshBuilder.WallTopSub);
            mb.Prism(h, 3 * h, zA, zB, bot, prevY + WallHeight, bot, FloorY + WallHeight, all, MeshBuilder.WallTopSub);

            if (Index == 0) // back wall so you can't slide off the start
                mb.Prism(-3 * h, 3 * h, zA - TileSize, zA, bot, WallHeight, bot, WallHeight, all, MeshBuilder.WallTopSub);
        }

        /// <summary>Climb-ramp booster trigger + chevrons. Skipped on the flat start section.</summary>
        void SpawnClimbBoost()
        {
            float h = TileSize * 0.5f;
            float prevY = FloorYOf(Index - 1);
            float zA = Z0 - h, zB = Z0 + (RampTiles - 0.5f) * TileSize;
            if (FloorY <= prevY) return; // start section is flat: geometry only, no booster
            // Small booster over the slope, launching uphill (+Z) toward the maze.
            float midY = (prevY + FloorY) * 0.5f, midZ = (zA + zB) * 0.5f;
            var go = new GameObject("Climb Boost");
            go.transform.SetParent(transform, false);
            go.transform.position = new Vector3(0f, midY + TileSize, midZ);
            var box = go.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = new Vector3(TileSize * 0.9f, Mathf.Abs(FloorY - prevY) + TileSize * 2f, (zB - zA) + TileSize);
            var boost = go.AddComponent<BoostRamp>();
            boost.up = new Vector3(0f, 0f, 1f);
            boost.top = new Vector3(0f, FloorY, zB);
            boost.landing = TileCenter(Center, LaunchTiles - 1);
            boost.hop = WallHeight;

            float slope = Mathf.Atan2(FloorY - prevY, zB - zA) * Mathf.Rad2Deg;
            int chevrons = Mathf.Max(2, Mathf.RoundToInt((zB - zA) / (TileSize * 1.5f)));
            for (int i = 0; i < chevrons; i++)
            {
                float f = (i + 0.5f) / chevrons;
                var p = new Vector3(0f, Mathf.Lerp(prevY, FloorY, f) + 0.06f * TileSize, Mathf.Lerp(zA, zB, f));
                for (int side = -1; side <= 1; side += 2)
                {
                    var bar = Decor(PrimitiveType.Cube, go.transform, Vector3.zero, new Vector3(TileSize * 0.45f, 0.04f * TileSize, TileSize * 0.12f), Visuals.Boost);
                    bar.transform.position = p + new Vector3(side * TileSize * 0.17f, 0f, 0f);
                    bar.transform.rotation = Quaternion.Euler(-slope, side * 35f, 0f);
                }
            }
        }

        void FinishMesh(MeshBuilder mb)
        {
            var mesh = mb.Build(name);
            gameObject.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = gameObject.AddComponent<MeshRenderer>();
            mr.sharedMaterials = new[] { Visuals.FloorTop, Visuals.WallSide, Visuals.WallTop, Visuals.Ramp };
            // MeshBuilder emits each quad with its own vertices; weld them so the collision surface is one clean mesh.
            var mc = gameObject.AddComponent<MeshCollider>();
            mc.cookingOptions = MeshColliderCookingOptions.CookForFasterSimulation | MeshColliderCookingOptions.EnableMeshCleaning
                              | MeshColliderCookingOptions.WeldColocatedVertices | MeshColliderCookingOptions.UseFastMidphase;
            mc.sharedMesh = mesh;
            mc.hasModifiableContacts = true; // slock clears friction on wall-side contacts
        }

        /// <summary>Blast one wall block (maze-local <paramref name="tx"/>, <paramref name="tz"/>) into open floor,
        /// e.g. the slock's emergency slug. Rebuilds the mesh; adds no pellet, so the gate count is unchanged.</summary>
        public bool TryBlastWall(int tx, int tz)
        {
            if (Tiles == null || tx < 0 || tx >= W || tz < 0 || tz >= L) return false;
            if (tx == 0 || tx == W - 1 || tz == 0 || tz == L - 1) return false; // outer boundary: never (no falling off)
            if (Tiles[tx, tz] != Tile.Wall) return false;
            Tiles[tx, tz] = Tile.Floor;
            RebuildMesh();
            return true;
        }

        /// <summary>Rebuild the render + collision mesh from the current tiles (geometry only: boosters are kept).</summary>
        void RebuildMesh()
        {
            var mb = new MeshBuilder(TileSize, Z0, FloorY);
            foreach (var r in rooms) // only left edge rooms exist; replay their prisms from the stored room
            {
                int rampLen = Mathf.Abs(r.ix0) - Center - 1;
                float xNear = -(Center + 0.5f) * TileSize, xFar = xNear - rampLen * TileSize;
                AddSideRampGeometry(mb, xFar, xNear, r.floorY, FloorY, r.k0 + r.entrance);
                AddTiles(mb, r.t, r.depth, r.floorY, r.Key, r.sign);
            }
            AddTiles(mb, Tiles, mainDepth, FloorY, MainKey, 1);
            BuildClimbRampGeometry(mb);
            var mesh = mb.Build(name);
            var mf = GetComponent<MeshFilter>();
            if (mf != null)
            {
                if (mf.sharedMesh != null) Destroy(mf.sharedMesh);
                mf.sharedMesh = mesh;
            }
            var mc = GetComponent<MeshCollider>();
            if (mc != null)
            {
                mc.sharedMesh = null;
                mc.sharedMesh = mesh;
            }
        }

        // ------------------------------------------------------------------ contents

        void SpawnCheckpoint()
        {
            var c = TileCenter(Center, L - 1);
            var go = checkpoint = new GameObject("Checkpoint");
            go.transform.SetParent(transform, false);
            go.transform.position = c + Vector3.up * 1f;
            var box = go.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = new Vector3(TileSize, 2f, TileSize * 0.4f);
            go.AddComponent<Checkpoint>().ChunkIndex = Index;

            // Locked gate: a solid glowing block in the exit until every pellet is eaten.
            gate = GameObject.CreatePrimitive(PrimitiveType.Cube);
            gate.name = "Gate";
            gate.transform.SetParent(go.transform, false);
            gate.transform.localPosition = new Vector3(0, -1f + WallHeight * 0.6f, 0);
            gate.transform.localScale = new Vector3(TileSize, WallHeight * 1.2f, TileSize);
            gate.GetComponent<MeshRenderer>().sharedMaterial = Visuals.Gate;

            // Glowing strip on the floor plus a bar across the wall tops.
            Decor(PrimitiveType.Cube, go.transform, new Vector3(0, -0.98f, 0), new Vector3(TileSize * 0.9f, 0.04f, TileSize * 0.3f), Visuals.Checkpoint);
            Decor(PrimitiveType.Cube, go.transform, new Vector3(0, WallHeight - 0.4f, 0), new Vector3(TileSize * 3f, 0.12f * TileSize, 0.12f * TileSize), Visuals.Checkpoint);
        }

        void SpawnPickup(Pickup.Kind kind, Vector2Int key, float floorY)
        {
            var go = new GameObject(kind + " Pickup");
            go.transform.SetParent(transform, false);
            go.transform.position = KeyCenter(key, floorY) + Vector3.up * 0.6f * TileSize;
            go.transform.localScale = Vector3.one * TileSize;
            var col = go.AddComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = 0.45f;
            go.AddComponent<Pickup>().kind = kind;
            reserved.Add(key);
        }

        void SpawnPickups(System.Random rng, Difficulty d)
        {
            var deadEnds = new List<Vector2Int>();
            var others = new List<Vector2Int>();
            for (int x = 1; x < W - 1; x++)
            for (int z = 2; z < L - 2; z++)
            {
                if (!IsFloor(x, z)) continue;
                if (penCells.Contains(new(x, z))) continue; // slorm pen: no pickups inside
                int n = (IsFloor(x + 1, z) ? 1 : 0) + (IsFloor(x - 1, z) ? 1 : 0) + (IsFloor(x, z + 1) ? 1 : 0) + (IsFloor(x, z - 1) ? 1 : 0);
                (n == 1 ? deadEnds : others).Add(new(x, z));
            }
            Shuffle(deadEnds, rng);
            Shuffle(others, rng);
            deadEnds.AddRange(others);

            for (int i = 0; i < Mathf.Min(d.Pickups, deadEnds.Count); i++)
                SpawnPickup(Pickup.Kind.Power, MainKey(deadEnds[i].x, deadEnds[i].y), FloorY);
        }

        static readonly Pickup.Kind[] PowerupKinds =
            { Pickup.Kind.ClearDots, Pickup.Kind.Steel, Pickup.Kind.RefreshSlugs, Pickup.Kind.ExtraSlug, Pickup.Kind.CloseTraps };

        const int PowerupCount = 3;          // powerups out at once in a section
        const float PowerupRespawn = 10f;    // seconds after one is taken until a new one appears
        int clearDotsSpawned, closeTrapsSpawned;
        readonly List<float> powerupDue = new();

        /// <summary>Three random powerups on random open blocks of the main maze.</summary>
        void SpawnPowerups(System.Random rng)
        {
            var spots = PowerupSpots(false);
            Shuffle(spots, rng);
            for (int i = 0; i < Mathf.Min(PowerupCount, spots.Count); i++)
                SpawnPickup(NextPowerupKind(() => rng.Next(PowerupKinds.Length)), MainKey(spots[i].x, spots[i].y), FloorY);
        }

        /// <summary>A random powerup kind. Clear-the-dots and close-the-traps each come at most once per section
        /// (respawns included).</summary>
        Pickup.Kind NextPowerupKind(System.Func<int> roll)
        {
            Pickup.Kind kind;
            do kind = PowerupKinds[roll()];
            while ((kind == Pickup.Kind.ClearDots && clearDotsSpawned > 0) || (kind == Pickup.Kind.CloseTraps && closeTrapsSpawned > 0));
            if (kind == Pickup.Kind.ClearDots) clearDotsSpawned++;
            if (kind == Pickup.Kind.CloseTraps) closeTrapsSpawned++;
            return kind;
        }

        /// <summary>Open main-maze blocks a powerup could go on (reachable, not the pen, not taken). With
        /// <paramref name="cleared"/>, only blocks with no pellet left (somewhere you've already been).</summary>
        List<Vector2Int> PowerupSpots(bool cleared)
        {
            var reach = DistanceMap(Tiles, new Vector2Int(Center, 0));
            var spots = new List<Vector2Int>();
            for (int x = 1; x < W - 1; x++)
            for (int z = 2; z < L - 2; z++)
            {
                var k = MainKey(x, z);
                if (reach[x, z] < 0 || penCells.Contains(new(x, z)) || reserved.Contains(k)) continue;
                if (cleared && pellets.ContainsKey(k)) continue;
                spots.Add(new(x, z));
            }
            return spots;
        }

        /// <summary>A powerup here was taken: a new random one appears <see cref="PowerupRespawn"/> seconds later.</summary>
        public void PowerupTaken(Pickup pickup)
        {
            reserved.Remove(KeyAt(pickup.transform.position));
            powerupDue.Add(Time.time + PowerupRespawn);
        }

        /// <summary>Spawn any powerups that are due, on a random cleared block away from the slock. Stops once the
        /// player has left the section.</summary>
        void RespawnPowerups()
        {
            if (exitSealed || powerupDue.Count == 0 || GameManager.I == null) return;
            var slockKey = KeyAt(GameManager.I.SlockPosition);
            for (int i = powerupDue.Count - 1; i >= 0; i--)
            {
                if (Time.time < powerupDue[i]) continue;
                var spots = PowerupSpots(true);
                spots.RemoveAll(c => { var k = MainKey(c.x, c.y); return Mathf.Abs(k.x - slockKey.x) + Mathf.Abs(k.y - slockKey.y) < 3; });
                if (spots.Count == 0) return; // nowhere yet: try again next frame
                var c = spots[Random.Range(0, spots.Count)];
                SpawnPickup(NextPowerupKind(() => Random.Range(0, PowerupKinds.Length)), MainKey(c.x, c.y), FloorY);
                powerupDue.RemoveAt(i);
            }
        }

        /// <summary>Deepest spot: a big clock or (rarer) the gate key. Another far spot: a power gem.</summary>
        void SpawnRoomRewards(SideRoom r, System.Random rng)
        {
            var dist = DistanceMap(r.t, new Vector2Int(0, r.entrance));
            var spots = new List<Vector2Int>();
            for (int x = 0; x < r.t.GetLength(0); x++)
            for (int z = 0; z < r.t.GetLength(1); z++)
                if (dist[x, z] > 1) spots.Add(new(x, z));
            if (spots.Count < 2) return;
            spots.Sort((a, b) => dist[b.x, b.y].CompareTo(dist[a.x, a.y]));

            var special = rng.NextDouble() < 0.35 ? Pickup.Kind.Key : Pickup.Kind.Clock;
            SpawnPickup(special, r.Key(spots[0].x, spots[0].y), r.floorY);
            var gem = spots[Mathf.Min(spots.Count - 1, spots.Count / 3)];
            SpawnPickup(Pickup.Kind.Power, r.Key(gem.x, gem.y), r.floorY);
        }

        void SpawnPellets()
        {
            var root = new GameObject("Pellets").transform;
            root.SetParent(transform, false);

            var reach = DistanceMap(Tiles, new Vector2Int(Center, 0));
            for (int x = 0; x < W; x++)
            for (int z = 0; z < L - 1; z++) // not the exit tile: that's where the gate sits
                if (reach[x, z] >= 0 && !penCells.Contains(new(x, z))) AddPellet(root, MainKey(x, z), FloorY, false);

            foreach (var r in rooms)
            {
                var d = DistanceMap(r.t, new Vector2Int(0, r.entrance));
                for (int x = 0; x < r.t.GetLength(0); x++)
                for (int z = 0; z < r.t.GetLength(1); z++)
                    if (d[x, z] >= 0) AddPellet(root, r.Key(x, z), r.floorY, true);
            }
            if (PelletsLeft == 0) OpenGate();
        }

        void AddPellet(Transform root, Vector2Int key, float floorY, bool gold)
        {
            if (reserved.Contains(key) || pellets.ContainsKey(key)) return;
            float size = (gold ? 0.28f : 0.23f) * TileSize;
            var p = Decor(PrimitiveType.Sphere, root, Vector3.zero, Vector3.one * size, gold ? Visuals.GoldPellet : Visuals.Pellet);
            p.transform.position = KeyCenter(key, floorY) + Vector3.up * 0.3f * TileSize;
            p.GetComponent<MeshRenderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            pellets[key] = new Pellet { go = p, gold = gold };
            floaters.Add(new Floater
            {
                t = p.transform,
                home = p.transform.position,
                phase = Random.value * 100f,
                spin = Random.Range(40f, 140f) * (Random.value < 0.5f ? -1f : 1f),
                bob = Random.Range(1.2f, 2.4f),
            });
        }

        // Pellet spheres: spin at their own speed and direction, and bob up and down out of step.
        void Update()
        {
            RespawnPowerups();
            float time = Time.time, amp = 0.06f * TileSize;
            for (int i = floaters.Count - 1; i >= 0; i--)
            {
                var f = floaters[i];
                if (f.t == null) { floaters.RemoveAt(i); continue; } // eaten
                float ph = f.phase + time;
                f.t.SetPositionAndRotation(
                    f.home + Vector3.up * Mathf.Sin(ph * f.bob) * amp,
                    Quaternion.Euler(Mathf.Sin(ph * 0.7f) * 8f, ph * f.spin, Mathf.Cos(ph * 0.9f) * 8f));
            }
        }

        /// <summary>World positions of all currently uneaten pellets (main maze + side rooms).</summary>
        public List<Vector3> UneatenPelletPositions()
        {
            var list = new List<Vector3>(pellets.Count);
            foreach (var kv in pellets)
                if (kv.Value.go != null) list.Add(kv.Value.go.transform.position);
            return list;
        }

        /// <summary>Eat the pellet on the block under <paramref name="world"/>, if any (main maze or side room).</summary>
        public bool TryEatPellet(Vector3 world, out bool gold)
        {
            gold = false;
            var key = KeyAt(world);
            if (!pellets.TryGetValue(key, out var p)) return false;
            // Only eat what we're actually level with (not a pellet on a floor far above/below us).
            if (Mathf.Abs(p.go.transform.position.y - world.y) > TileSize * 1.5f) return false;
            gold = p.gold;
            Destroy(p.go);
            pellets.Remove(key);
            return true;
        }

        /// <summary>Powerup: remove a random <paramref name="fraction"/> of the uneaten pellets (rounded up). Returns how many.</summary>
        public int RemovePellets(float fraction)
        {
            var keys = new List<Vector2Int>(pellets.Keys);
            for (int i = keys.Count - 1; i > 0; i--)
            {
                int j = Random.Range(0, i + 1);
                (keys[i], keys[j]) = (keys[j], keys[i]);
            }
            int n = Mathf.CeilToInt(keys.Count * fraction);
            for (int i = 0; i < n; i++)
            {
                Destroy(pellets[keys[i]].go);
                pellets.Remove(keys[i]);
            }
            return n;
        }

        /// <summary>Powerup: fill every hole in this section (main maze and side rooms) with floor, and wall up every
        /// gap in their outer walls (not the entry, exit or side-room doorway, nor the block <paramref name="slock"/>
        /// stands on). Pellets on walled-up blocks go too. Returns how many traps were closed.</summary>
        public int CloseTraps(Vector3 slock)
        {
            var standing = KeyAt(slock);
            int n = Close(Tiles, MainKey, (x, z) => (x == Center && (z == 0 || z == L - 1)) || (x == 0 && z == edgeRoomRow));
            foreach (var r in rooms) n += Close(r.t, r.Key, (x, z) => x == 0 && z == r.entrance);
            if (n > 0) RebuildMesh();
            return n;

            int Close(Tile[,] t, System.Func<int, int, Vector2Int> key, System.Func<int, int, bool> doorway)
            {
                int w = t.GetLength(0), l = t.GetLength(1), closed = 0;
                for (int x = 0; x < w; x++)
                for (int z = 0; z < l; z++)
                {
                    if (t[x, z] == Tile.Void) { t[x, z] = Tile.Floor; closed++; continue; }
                    bool edge = x == 0 || x == w - 1 || z == 0 || z == l - 1;
                    var k = key(x, z);
                    if (!edge || t[x, z] != Tile.Floor || doorway(x, z) || k == standing || reserved.Contains(k)) continue;
                    t[x, z] = Tile.Wall;
                    closed++;
                    if (pellets.TryGetValue(k, out var p)) { Destroy(p.go); pellets.Remove(k); }
                }
                return closed;
            }
        }

        /// <summary>The player has gone through: wall the exit up behind them so this section can't be re-entered
        /// (an outer-boundary block, so slugs can't reopen it).</summary>
        public void SealExit()
        {
            if (exitSealed || Tiles == null) return;
            exitSealed = true;
            Tiles[Center, L - 1] = Tile.Wall;
            RebuildMesh();
            if (checkpoint != null) Destroy(checkpoint);
            gate = null;
        }

        public void OpenGate()
        {
            if (gate != null) Destroy(gate);
            gate = null;
        }

        void SpawnWorms(System.Random rng, Difficulty d)
        {
            // Slorms start in the centre pen (Pac-Man style) and crawl out through its opening.
            var homes = new List<Vector2Int>();
            foreach (var c in penHomes)
                if (IsCrawlable(c.x, c.y)) homes.Add(c);
            Shuffle(homes, rng);

            var cells = new List<Vector2Int>();
            for (int x = 1; x < W - 1; x++)
            for (int z = 5; z < L - 2; z++)
                if (IsCrawlable(x, z)) cells.Add(new(x, z));
            Shuffle(cells, rng);

            for (int i = 0; i < d.Worms; i++)
            {
                Vector2Int cell;
                if (homes.Count > 0) cell = homes[i % homes.Count];
                else if (i < cells.Count) cell = cells[i];
                else break;
                var go = new GameObject("Worm");
                go.transform.SetParent(transform, false);
                var worm = go.AddComponent<Worm>();
                worm.Init(this, cell, d.WormSpeed, rng.Next());
                slorms.Add(worm);
            }
        }

        const float SlormReleaseGap = 4f;   // seconds between slorms leaving the pen
        bool slormsReleased;

        /// <summary>The player has entered this section: let its slorms out of the pen one at a time, Pac-Man style.</summary>
        public void ReleaseSlorms()
        {
            if (slormsReleased) return;
            slormsReleased = true;
            for (int i = 0; i < slorms.Count; i++) slorms[i].ReleaseAt(Time.time + i * SlormReleaseGap);
        }

        /// <summary>All slorms in this section (including eaten ones waiting to respawn).</summary>
        public IReadOnlyList<Worm> Slorms => slorms;

        public static GameObject Decor(PrimitiveType type, Transform parent, Vector3 localPos, Vector3 scale, Material mat)
        {
            var go = GameObject.CreatePrimitive(type);
            DestroyImmediate(go.GetComponent<Collider>());
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            go.transform.localScale = scale;
            go.GetComponent<MeshRenderer>().sharedMaterial = mat;
            return go;
        }

        static void Shuffle<T>(List<T> list, System.Random rng)
        {
            for (int i = list.Count - 1; i > 0; i--)
            {
                int j = rng.Next(i + 1);
                (list[i], list[j]) = (list[j], list[i]);
            }
        }

        void OnDestroy()
        {
            var mf = GetComponent<MeshFilter>();
            if (mf != null && mf.sharedMesh != null) Destroy(mf.sharedMesh);
        }
    }

    /// <summary>How nasty chunk N is. Everything ramps up and then plateaus.</summary>
    public struct Difficulty
    {
        public float LoopChance, PitChance, OpenEdgeChance, WormSpeed, TimeBonus, EdgeRoomChance;
        public int MinRooms, MaxRooms, Pickups, Worms;

        public static Difficulty For(int i) => new()
        {
            LoopChance = Mathf.Max(0.005f, 0.3f - i * 0.3f),
            PitChance = Mathf.Min(0.5f, 0.2f + i * 0.05f),
            OpenEdgeChance = Mathf.Min(0.95f, 0.4f + i * 0.06f),
            MinRooms = 2,
            MaxRooms = 4,
            Pickups = 3 + Mathf.Min(3, i / 3),
            Worms = 4 + i,                         // Pac-Man: 4 to start, one more per section
            WormSpeed = Mathf.Min(20.6f, 15f + i * 0.3f),    // tiles/s
            TimeBonus = Mathf.Max(7f, 18f - i * 0.5f),
            EdgeRoomChance = i == 0 ? 1f : 0.7f,   // the first section always shows one off
        };
    }
}
