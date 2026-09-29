using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Slock
{
    /// <summary>Accumulates flat-shaded prisms into one mesh with floor-top, side and wall-top submeshes.</summary>
    public class MeshBuilder
    {
        public const int TopSub = 0, SideSub = 1, WallTopSub = 2;

        [System.Flags]
        public enum Faces { None = 0, Top = 1, PosX = 2, NegX = 4, PosZ = 8, NegZ = 16, AllSides = PosX | NegX | PosZ | NegZ, All = Top | AllSides }

        readonly List<Vector3> verts = new();
        readonly List<Vector3> normals = new();
        readonly List<Vector2> uvs = new();
        readonly List<int>[] tris = { new(), new(), new() };
        readonly float uvScale, zOrigin, yOrigin;
        const float BlocksPerTexture = 2f; // each tile texture spans 2x2 blocks, so its panel lines fall on block edges

        /// <param name="zOrigin">World Z of a block centre (grids start at different Z per section).</param>
        /// <param name="yOrigin">World Y of the floor, so wall-side panels line up with it.</param>
        public MeshBuilder(float tileSize, float zOrigin, float yOrigin)
        {
            uvScale = 1f / tileSize;
            this.zOrigin = zOrigin;
            this.yOrigin = yOrigin;
        }

        /// <summary>
        /// A box spanning x0..x1, z0..z1 whose bottom/top heights may differ between the z0 and z1 ends (for ramps).
        /// </summary>
        public void Prism(float x0, float x1, float z0, float z1, float bot0, float top0, float bot1, float top1, Faces faces, int topSub = TopSub)
        {
            var center = new Vector3((x0 + x1) * 0.5f, (bot0 + top0 + bot1 + top1) * 0.25f, (z0 + z1) * 0.5f);

            if ((faces & Faces.Top) != 0)
                Quad(new(x0, top0, z0), new(x1, top0, z0), new(x1, top1, z1), new(x0, top1, z1), center, topSub, UvTop);
            if ((faces & Faces.PosX) != 0)
                Quad(new(x1, bot0, z0), new(x1, bot1, z1), new(x1, top1, z1), new(x1, top0, z0), center, SideSub, UvZY);
            if ((faces & Faces.NegX) != 0)
                Quad(new(x0, bot0, z0), new(x0, top0, z0), new(x0, top1, z1), new(x0, bot1, z1), center, SideSub, UvZY);
            if ((faces & Faces.PosZ) != 0)
                Quad(new(x0, bot1, z1), new(x0, top1, z1), new(x1, top1, z1), new(x1, bot1, z1), center, SideSub, UvXY);
            if ((faces & Faces.NegZ) != 0)
                Quad(new(x0, bot0, z0), new(x1, bot0, z0), new(x1, top0, z0), new(x0, top0, z0), center, SideSub, UvXY);
        }

        /// <summary>Like <see cref="Prism"/>, but the bottom/top heights vary along X instead of Z (side ramps).</summary>
        public void PrismX(float x0, float x1, float z0, float z1, float bot0, float top0, float bot1, float top1, Faces faces, int topSub = TopSub)
        {
            var center = new Vector3((x0 + x1) * 0.5f, (bot0 + top0 + bot1 + top1) * 0.25f, (z0 + z1) * 0.5f);

            if ((faces & Faces.Top) != 0)
                Quad(new(x0, top0, z0), new(x1, top1, z0), new(x1, top1, z1), new(x0, top0, z1), center, topSub, UvTop);
            if ((faces & Faces.PosX) != 0)
                Quad(new(x1, bot1, z0), new(x1, bot1, z1), new(x1, top1, z1), new(x1, top1, z0), center, SideSub, UvZY);
            if ((faces & Faces.NegX) != 0)
                Quad(new(x0, bot0, z0), new(x0, top0, z0), new(x0, top0, z1), new(x0, bot0, z1), center, SideSub, UvZY);
            if ((faces & Faces.PosZ) != 0)
                Quad(new(x0, bot0, z1), new(x0, top0, z1), new(x1, top1, z1), new(x1, bot1, z1), center, SideSub, UvXY);
            if ((faces & Faces.NegZ) != 0)
                Quad(new(x0, bot0, z0), new(x1, bot1, z0), new(x1, top1, z0), new(x0, top0, z0), center, SideSub, UvXY);
        }

        // Block coordinates: block centres sit on whole numbers, so +0.5 puts texture edges on block edges;
        // dividing by BlocksPerTexture spreads one texture over several blocks.
        float U(float x) => (x * uvScale + 0.5f) / BlocksPerTexture;
        float W(float z) => ((z - zOrigin) * uvScale + 0.5f) / BlocksPerTexture;
        float V(float y) => (y - yOrigin) * uvScale / BlocksPerTexture;
        Vector2 UvTop(Vector3 p) => new(U(p.x), W(p.z));
        Vector2 UvZY(Vector3 p) => new(W(p.z), V(p.y));
        Vector2 UvXY(Vector3 p) => new(U(p.x), V(p.y));

        void Quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 center, int sub, System.Func<Vector3, Vector2> uv)
        {
            var n = Vector3.Cross(b - a, c - a).normalized;
            var outward = (a + b + c + d) * 0.25f - center;
            if (Vector3.Dot(n, outward) < 0f) { (b, d) = (d, b); n = -n; }

            int i = verts.Count;
            verts.Add(a); verts.Add(b); verts.Add(c); verts.Add(d);
            for (int k = 0; k < 4; k++) normals.Add(n);
            uvs.Add(uv(a)); uvs.Add(uv(b)); uvs.Add(uv(c)); uvs.Add(uv(d));
            var t = tris[sub];
            t.Add(i); t.Add(i + 1); t.Add(i + 2);
            t.Add(i); t.Add(i + 2); t.Add(i + 3);
        }

        public Mesh Build(string name)
        {
            var mesh = new Mesh { name = name, indexFormat = IndexFormat.UInt32, subMeshCount = 3 };
            mesh.SetVertices(verts);
            mesh.SetNormals(normals);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris[0], 0);
            mesh.SetTriangles(tris[1], 1);
            mesh.SetTriangles(tris[2], 2);
            mesh.RecalculateTangents(); // needed by the tile normal maps
            mesh.RecalculateBounds();
            return mesh;
        }
    }
}
