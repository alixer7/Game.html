using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Procedural stylised-realistic decorations. Solid geometry goes into 'mb', alpha-cutout foliage cards into 'fol'
    /// (atlas cells, see Art.FoliageAtlas), emissive bits (lava, lamps) into 'glow'.
    /// </summary>
    public static class PropFactory
    {
        public const int CellGrass = 0, CellFern = 1, CellPalm = 2, CellLeaf = 3, CellFlower = 4, CellReed = 5, CellPine = 6, CellVine = 7;
        static float U0(int cell) { return cell / 8f + 0.004f; }
        static float U1(int cell) { return (cell + 1) / 8f - 0.004f; }

        static Color H(string hex) { Color c; ColorUtility.TryParseHtmlString(hex, out c); return c; }
        static Matrix4x4 M(Vector3 p, Quaternion r, Vector3 s) { return Matrix4x4.TRS(p, r, s); }
        static Matrix4x4 M(Vector3 p) { return Matrix4x4.TRS(p, Quaternion.identity, Vector3.one); }

        // ================================================================ dispatch
        /// <summary>Places one roadside prop and returns its collision radius (0 = pass-through foliage).</summary>
        public static float Place(MeshBuilder mb, MeshBuilder fol, MeshBuilder glow, ZoneStyle z, Vector3 p, Rng rng, float water)
        {
            float r = rng.Value();
            float sc;
            switch (z.Decor)
            {
                case DecorSet.Jungle:
                    if (r < 0.45f) { sc = rng.Range(0.9f, 1.4f); JungleTree(mb, fol, p, sc, rng); return 0.5f * sc; }
                    if (r < 0.6f) { sc = rng.Range(0.9f, 1.2f); PalmTree(mb, fol, p, sc, rng); return 0.45f * sc; }
                    if (r < 0.8f) { Bush(fol, p, rng.Range(1.2f, 2f), H("#3F9A3A"), rng); return 0f; }
                    if (r < 0.9f) { sc = rng.Range(1f, 2.4f); Rock(mb, p, sc, z.Cliff, H("#4E8A34"), rng); return sc * 0.85f; }
                    sc = rng.Range(0.8f, 1.2f); Stump(mb, fol, p, sc, rng); return 0.8f * sc;
                case DecorSet.Temple:
                    if (r < 0.28f) { sc = rng.Range(0.9f, 1.3f); Column(mb, fol, p, sc, z, rng); return 0.85f * sc; }
                    if (r < 0.38f) { sc = rng.Range(0.8f, 1.2f); StoneHead(mb, fol, p, rng.Range(0, 360f), sc, z); return 1.4f * sc; }
                    if (r < 0.55f) { Ruins(mb, fol, p, z, rng); return 2.6f; }
                    if (r < 0.78f) { sc = rng.Range(0.9f, 1.3f); JungleTree(mb, fol, p, sc, rng); return 0.5f * sc; }
                    if (r < 0.88f) { Torch(mb, glow, p, 1.1f); return 0.25f; }
                    sc = rng.Range(1f, 2.2f); Rock(mb, p, sc, z.Cliff, H("#5E8A3C"), rng); return sc * 0.85f;
                case DecorSet.Volcano:
                    if (r < 0.38f) { sc = rng.Range(1.2f, 3f); LavaRock(mb, glow, p, sc, z, rng); return sc * 0.85f; }
                    if (r < 0.55f) { sc = rng.Range(0.9f, 1.4f); DeadTree(mb, p, sc, rng); return 0.4f * sc; }
                    if (r < 0.7f) { LavaPool(glow, mb, p, rng.Range(2f, 4f), rng); return 0f; }
                    if (r < 0.88f) { sc = rng.Range(0.8f, 1.5f); Obsidian(mb, p, sc, rng); return 0.8f * sc; }
                    Torch(mb, glow, p, 1.2f); return 0.25f;
                case DecorSet.Desert:
                case DecorSet.Mesa:
                    if (r < 0.38f) { sc = rng.Range(0.8f, 1.35f); Cactus(mb, p, sc, rng); return 0.45f * sc; }
                    if (r < 0.65f) { sc = rng.Range(1.2f, 3.2f); Rock(mb, p, sc, z.Cliff, z.TerrainHigh, rng); return sc * 0.85f; }
                    if (r < 0.78f) { DryBush(fol, p, rng.Range(0.8f, 1.4f), rng); return 0f; }
                    if (r < 0.92f) { sc = rng.Range(2.5f, 4.5f); Mesa(mb, p, sc, rng.Range(5f, 10f), z, rng); return sc; }
                    SignPost(mb, p, rng.Range(0, 360f)); return 0.2f;
                case DecorSet.Mine:
                    if (r < 0.22f) { MineCart(mb, p, rng.Range(0, 360f)); return 1.3f; }
                    if (r < 0.42f) { Barrels(mb, p, rng); return 1.1f; }
                    if (r < 0.6f) { CrateStack(mb, p, rng); return 1.3f; }
                    if (r < 0.85f) { sc = rng.Range(1.2f, 3f); Rock(mb, p, sc, z.Cliff, z.TerrainHigh, rng); return sc * 0.85f; }
                    Lantern(mb, glow, p, 1f); return 0.2f;
                case DecorSet.River:
                    if (r < 0.3f) { sc = rng.Range(0.8f, 1.1f); JungleTree(mb, fol, p, sc, rng, H("#8DB843")); return 0.5f * sc; }
                    if (r < 0.55f) { sc = rng.Range(1f, 2.5f); Rock(mb, p, sc, z.Cliff, z.TerrainMid, rng); return sc * 0.85f; }
                    if (r < 0.75f) { Reeds(fol, p, rng); return 0f; }
                    if (r < 0.9f) { Log(mb, p, rng); return 0.9f; }
                    sc = rng.Range(0.8f, 1.1f); Cactus(mb, p, sc, rng); return 0.45f * sc;
                case DecorSet.Village:
                    if (r < 0.25f) { sc = rng.Range(0.9f, 1.2f); Cabin(mb, glow, p, rng.Range(0, 360f), sc, rng); return 2.6f * sc; }
                    if (r < 0.65f) { sc = rng.Range(0.9f, 1.4f); PineTree(mb, fol, p, sc, rng); return 0.5f * sc; }
                    if (r < 0.8f) { Lantern(mb, glow, p, 1.1f); return 0.2f; }
                    if (r < 0.9f) { sc = rng.Range(0.8f, 1.1f); Snowman(mb, p, rng.Range(0, 360f), sc); return 1.0f * sc; }
                    sc = rng.Range(1f, 2.4f); Rock(mb, p, sc, z.Cliff, Color.white, rng); return sc * 0.85f;
                case DecorSet.IceCave:
                    if (r < 0.6f) { sc = rng.Range(0.7f, 1.3f); IceCrystal(mb, glow, p, sc, rng); return 0.9f * sc; }
                    sc = rng.Range(1.2f, 2.8f); Rock(mb, p, sc, H("#7FA8D0"), H("#E8F6FF"), rng); return sc * 0.85f;
                case DecorSet.Lake:
                case DecorSet.Alpine:
                    if (r < 0.55f) { sc = rng.Range(0.9f, 1.5f); PineTree(mb, fol, p, sc, rng); return 0.5f * sc; }
                    if (r < 0.85f) { sc = rng.Range(1.2f, 3f); Rock(mb, p, sc, z.Cliff, Color.white, rng); return sc * 0.85f; }
                    if (r < 0.93f) { sc = rng.Range(0.7f, 1f); Igloo(mb, p, rng.Range(0, 360f), sc); return 2.9f * sc; }
                    sc = rng.Range(0.8f, 1.1f); Snowman(mb, p, rng.Range(0, 360f), sc); return 1.0f * sc;
                default: // beach
                    if (r < 0.55f) { sc = rng.Range(0.9f, 1.35f); PalmTree(mb, fol, p, sc, rng); return 0.45f * sc; }
                    if (r < 0.72f) { sc = rng.Range(1f, 2.6f); Rock(mb, p, sc, z.Cliff, H("#C9B48A"), rng); return sc * 0.85f; }
                    if (r < 0.84f) { Torch(mb, glow, p, rng.Range(0.9f, 1.2f)); return 0.25f; }
                    if (r < 0.94f) { sc = rng.Range(0.8f, 1f); TikiHut(mb, fol, p, rng.Range(0, 360f), sc); return 2.0f * sc; }
                    Log(mb, p, rng); return 0.9f;
            }
        }

        public static bool HasGroundCover(DecorSet d)
        {
            return d == DecorSet.Beach || d == DecorSet.Jungle || d == DecorSet.Temple || d == DecorSet.River || d == DecorSet.Desert || d == DecorSet.Mesa;
        }

        public static void GroundCover(MeshBuilder fol, ZoneStyle z, Vector3 p, Rng rng)
        {
            float r = rng.Value();
            switch (z.Decor)
            {
                case DecorSet.Jungle:
                    if (r < 0.45f) Fern(fol, p, rng.Range(0.8f, 1.5f), rng);
                    else if (r < 0.85f) Grass(fol, p, rng.Range(0.8f, 1.3f), H("#4FA83E"), rng);
                    else Flowers(fol, p, rng);
                    break;
                case DecorSet.Temple:
                    if (r < 0.6f) Grass(fol, p, rng.Range(0.7f, 1.1f), H("#6DA845"), rng);
                    else if (r < 0.85f) Fern(fol, p, rng.Range(0.7f, 1.1f), rng);
                    else Flowers(fol, p, rng);
                    break;
                case DecorSet.River:
                    if (r < 0.6f) Grass(fol, p, rng.Range(0.8f, 1.2f), H("#7DA650"), rng);
                    else Reeds(fol, p, rng);
                    break;
                case DecorSet.Desert:
                case DecorSet.Mesa:
                    if (r < 0.35f) Grass(fol, p, rng.Range(0.5f, 0.8f), H("#C9A45E"), rng);
                    break;
                default:
                    if (r < 0.7f) Grass(fol, p, rng.Range(0.6f, 1.0f), H("#7CC24E"), rng);
                    else if (r < 0.85f) Flowers(fol, p, rng);
                    break;
            }
        }

        /// <summary>Large distant prop; returns its collision radius.</summary>
        public static float Landmark(MeshBuilder mb, MeshBuilder fol, MeshBuilder glow, ZoneStyle z, Vector3 p, Rng rng, float water)
        {
            float sc;
            switch (z.Decor)
            {
                case DecorSet.Temple:
                    if (rng.Chance(0.5f)) { sc = rng.Range(14f, 22f); Pyramid(mb, fol, p, sc, z, rng); return sc * 0.5f; }
                    sc = rng.Range(3f, 4.5f); StoneHead(mb, fol, p, rng.Range(0, 360f), sc, z); return 1.4f * sc;
                case DecorSet.Volcano: sc = rng.Range(40f, 60f); VolcanoCone(mb, glow, p, sc, z, rng); return sc * 0.95f;
                case DecorSet.Desert: case DecorSet.Mesa: case DecorSet.Mine: case DecorSet.River:
                    sc = rng.Range(9f, 18f); Mesa(mb, p, sc, rng.Range(18f, 38f), z, rng); return sc;
                case DecorSet.Jungle: sc = rng.Range(2.2f, 3f); JungleTree(mb, fol, p, sc, rng); return 0.5f * sc;
                case DecorSet.Village: sc = rng.Range(1.8f, 2.4f); Cabin(mb, glow, p, rng.Range(0, 360f), sc, rng); return 2.6f * sc;
                case DecorSet.IceCave: case DecorSet.Lake: case DecorSet.Alpine: sc = rng.Range(2.5f, 4f); IceCrystal(mb, glow, p, sc, rng); return 0.9f * sc;
                default:
                    if (p.y < water) { sc = rng.Range(6f, 11f); Rock(mb, p, sc, z.Cliff, H("#8FA06A"), rng); return sc * 0.85f; }
                    sc = rng.Range(1.4f, 1.8f); TikiHut(mb, fol, p, rng.Range(0, 360f), sc); return 2.0f * sc;
            }
        }

        /// <summary>One hanging strand of a curtain (vine / icicle / rope), from 'top' straight down.</summary>
        public static void HangingStrand(MeshBuilder fol, Vector3 top, Vector3 side, float length, Color col, bool icy)
        {
            fol.AddFrond(top, Vector3.down, side.normalized, length, icy ? 0.35f : 0.6f, 0f, U0(CellVine), U1(CellVine), col, 3);
        }

        // ================================================================ foliage
        public static void Grass(MeshBuilder fol, Vector3 p, float s, Color col, Rng rng)
        {
            fol.AddCrossCards(p, 1.3f * s, 0.9f * s, rng.Range(0, 180f), U0(CellGrass), U1(CellGrass), rng.Jitter(col, 0.06f), 2, 0.6f);
        }

        public static void Fern(MeshBuilder fol, Vector3 p, float s, Rng rng)
        {
            Color c = rng.Jitter(H("#3E9B3A"), 0.05f);
            int n = rng.Range(5, 8);
            float yaw0 = rng.Range(0, 360f);
            for (int i = 0; i < n; i++)
            {
                float a = (yaw0 + i * 360f / n + rng.Range(-15, 15)) * Mathf.Deg2Rad;
                Vector3 dir = new Vector3(Mathf.Cos(a), 0.9f, Mathf.Sin(a)).normalized;
                Vector3 side = new Vector3(-Mathf.Sin(a), 0, Mathf.Cos(a));
                fol.AddFrond(p + Vector3.up * 0.05f, dir, side, 1.4f * s, 0.6f * s, 0.6f * s, U0(CellFern), U1(CellFern), c, 4);
            }
        }

        public static void Flowers(MeshBuilder fol, Vector3 p, Rng rng)
        {
            Color[] cols = { H("#FF5E8A"), H("#FFD23F"), H("#FF8A3D"), H("#B07CFF"), H("#FFFFFF") };
            fol.AddCrossCards(p, 0.9f, 0.6f, rng.Range(0, 180f), U0(CellFlower), U1(CellFlower), cols[rng.Range(0, cols.Length)], 2, 0.5f);
        }

        public static void Reeds(MeshBuilder fol, Vector3 p, Rng rng)
        {
            fol.AddCrossCards(p, 1.2f, rng.Range(1.6f, 2.3f), rng.Range(0, 180f), U0(CellReed), U1(CellReed), rng.Jitter(H("#8FB060"), 0.05f), 3, 0.8f);
        }

        public static void DryBush(MeshBuilder fol, Vector3 p, float s, Rng rng)
        {
            fol.AddCrossCards(p, 1.6f * s, 1.1f * s, rng.Range(0, 180f), U0(CellReed), U1(CellReed), rng.Jitter(H("#B8935A"), 0.05f), 3, 0.4f);
        }

        public static void Bush(MeshBuilder fol, Vector3 p, float s, Color col, Rng rng)
        {
            int n = rng.Range(6, 10);
            for (int i = 0; i < n; i++)
            {
                float a = rng.Range(0, Mathf.PI * 2f);
                Vector3 dir = new Vector3(Mathf.Cos(a), rng.Range(0.5f, 1.4f), Mathf.Sin(a)).normalized;
                Vector3 side = Vector3.Cross(Vector3.up, dir).normalized;
                fol.AddFrond(p + Vector3.up * 0.1f, dir, side, 1.3f * s, 1.0f * s, 0.3f * s, U0(CellLeaf), U1(CellLeaf), rng.Jitter(col, 0.06f), 3);
            }
        }

        // ================================================================ trees
        public static void PalmTree(MeshBuilder mb, MeshBuilder fol, Vector3 pos, float scale, Rng rng)
        {
            float lean = rng.Range(-20f, 20f), yaw = rng.Range(0, 360f);
            int segs = 9;
            var path = new Vector3[segs + 1]; var rad = new float[segs + 1];
            Vector3 p = pos;
            Vector3 dir = Quaternion.Euler(0, yaw, lean * 0.5f) * Vector3.up;
            float segLen = 0.95f * scale;
            for (int i = 0; i <= segs; i++)
            {
                path[i] = p; rad[i] = Mathf.Lerp(0.42f, 0.22f, i / (float)segs) * scale;
                p += dir * segLen;
                dir = (Quaternion.AngleAxis(lean * 0.09f, Quaternion.Euler(0, yaw, 0) * Vector3.forward) * dir).normalized;
            }
            mb.AddTube(path, rad, 9, H("#8A5E36"), H("#B88A58"));
            // bark rings
            for (int i = 1; i < segs; i++)
                mb.AddTorus(M(path[i], Quaternion.FromToRotation(Vector3.up, (path[i + 1] - path[i - 1]).normalized), Vector3.one), rad[i] * 1.02f, 0.05f * scale, 9, 3, H("#6E4626"));
            Vector3 top = path[segs];
            for (int i = 0; i < 3; i++)
            {
                Vector3 o = Quaternion.Euler(0, i * 120 + yaw, 0) * new Vector3(0.28f, -0.22f, 0) * scale;
                mb.AddSphere(M(top + o), 0.22f * scale, 6, 8, H("#6B4A24"), H("#3E2A14"));
            }
            int fronds = 9;
            for (int f = 0; f < fronds; f++)
            {
                float a = (yaw + f * 360f / fronds + rng.Range(-12, 12)) * Mathf.Deg2Rad;
                Vector3 d = new Vector3(Mathf.Cos(a), rng.Range(0.05f, 0.45f), Mathf.Sin(a)).normalized;
                Vector3 side = Vector3.Cross(Vector3.up, d).normalized;
                fol.AddFrond(top, d, side, rng.Range(3.6f, 4.6f) * scale, 1.5f * scale, rng.Range(1.4f, 2.2f) * scale, U0(CellPalm), U1(CellPalm), rng.Jitter(H("#45B23E"), 0.05f), 6);
            }
        }

        public static void JungleTree(MeshBuilder mb, MeshBuilder fol, Vector3 pos, float s, Rng rng, Color? leafCol = null)
        {
            Color bark = H("#6A4A30"), leaf = leafCol ?? H("#3E9A38");
            float h = rng.Range(5f, 8f) * s;
            var path = new Vector3[6]; var rad = new float[6];
            Vector3 bend = new Vector3(rng.Range(-1f, 1f), 0, rng.Range(-1f, 1f)) * 0.6f * s;
            for (int i = 0; i < 6; i++)
            {
                float t = i / 5f;
                path[i] = pos + Vector3.up * h * t + bend * Mathf.Sin(t * Mathf.PI);
                rad[i] = Mathf.Lerp(0.6f, 0.28f, t) * s;
            }
            mb.AddTube(path, rad, 8, bark * 0.85f, bark * 1.1f);
            // buttress roots
            for (int r = 0; r < 4; r++)
            {
                float a = r * 90f + rng.Range(-20, 20);
                Vector3 d = Quaternion.Euler(0, a, 0) * Vector3.forward;
                mb.AddTube(new[] { pos + Vector3.up * 1.2f * s, pos + d * 0.9f * s + Vector3.up * 0.3f * s, pos + d * 1.6f * s - Vector3.up * 0.2f }, new[] { 0.25f * s, 0.18f * s, 0.08f * s }, 5, bark * 0.8f);
            }
            // branches + ONE sculpted canopy: the clumps are lobes of a single leaf mass (no sphere stacks),
            // with a few leaf cards on the rim for a ragged silhouette
            Vector3 top = path[5];
            int clumps = rng.Range(4, 7);
            Vector3 cc = top + Vector3.up * 0.9f * s;
            var lobes = new Vector3[clumps + 1]; var radii = new float[clumps + 1];
            lobes[0] = Vector3.zero; radii[0] = 2.3f * s;
            for (int c = 0; c < clumps; c++)
            {
                float a = (c / (float)clumps * 360f + rng.Range(-25f, 25f)) * Mathf.Deg2Rad;
                Vector3 off = new Vector3(Mathf.Cos(a) * rng.Range(1.4f, 2.5f), rng.Range(-1.1f, 0.7f), Mathf.Sin(a) * rng.Range(1.4f, 2.5f)) * s;
                Vector3 cp = cc + off;
                mb.AddTube(new[] { top - Vector3.up * 0.8f * s, Vector3.Lerp(top, cp, 0.55f) + Vector3.up * 0.2f * s, cp - Vector3.up * 0.6f * s }, new[] { 0.24f * s, 0.15f * s, 0.07f * s }, 6, bark);
                lobes[c + 1] = off; radii[c + 1] = rng.Range(1.4f, 2.0f) * s;
                if (c % 2 == 0) Bush(fol, cp - Vector3.up * 1.1f * s, 1.3f * s, rng.Jitter(leaf, 0.06f), rng);
            }
            OrganicProps.Canopy(mb, cc, lobes, radii, rng.Jitter(leaf, 0.05f), rng.Range(0, 100000));
            // hanging vines
            for (int v = 0; v < 3; v++)
            {
                float a = rng.Range(0, 360f) * Mathf.Deg2Rad;
                Vector3 vp = top + new Vector3(Mathf.Cos(a), -0.4f, Mathf.Sin(a)) * 1.8f * s;
                fol.AddFrond(vp, Vector3.down, new Vector3(-Mathf.Sin(a), 0, Mathf.Cos(a)), rng.Range(2f, 3.5f) * s, 0.5f * s, 0f, U0(CellVine), U1(CellVine), leaf * 0.9f, 3);
            }
        }

        public static void PineTree(MeshBuilder mb, MeshBuilder fol, Vector3 pos, float s, Rng rng)
        {
            Color trunk = H("#5E4230"), dark = H("#1E5E46"), mid = H("#2C7A58"), snow = H("#F6FBFF");
            mb.AddCylinder(M(pos), 0.38f * s, 0.2f * s, 3.2f * s, 7, trunk);
            float y = 1.3f * s; float r = 2.6f * s;
            int tiers = 4 + rng.Range(0, 2);
            for (int i = 0; i < tiers; i++)
            {
                float h = 2.3f * s;
                // ragged drooping skirt (sculpted), snow on its upper faces
                Color c = i % 2 == 0 ? dark : mid;
                OrganicProps.PineTier(mb, pos + Vector3.up * y, r, h, dark, c, snow, rng.Range(0, 100000), true);
                for (int b = 0; b < 3; b++)
                {
                    float a = (b * 120f + i * 37f) * Mathf.Deg2Rad;
                    Vector3 d = new Vector3(Mathf.Cos(a), -0.15f, Mathf.Sin(a)).normalized;
                    fol.AddFrond(pos + Vector3.up * (y + 0.3f * h), d, Vector3.Cross(Vector3.up, d).normalized, r * 1.05f, 0.9f * s, 0.25f * s, U0(CellPine), U1(CellPine), c * 1.1f, 2);
                }
                y += h * 0.55f; r *= 0.74f;
            }
        }

        public static void DeadTree(MeshBuilder mb, Vector3 pos, float s, Rng rng)
        {
            Color c = H("#2E2624");
            var path = new[] { pos, pos + new Vector3(0.2f, 2f, 0.1f) * s, pos + new Vector3(-0.1f, 3.8f, 0.3f) * s, pos + new Vector3(0.3f, 5.2f, 0f) * s };
            mb.AddTube(path, new[] { 0.4f * s, 0.3f * s, 0.2f * s, 0.08f * s }, 6, c);
            for (int b = 0; b < 4; b++)
            {
                Vector3 st = path[1 + b % 2] + Vector3.up * rng.Range(0f, 0.8f);
                Vector3 d = new Vector3(rng.Range(-1f, 1f), rng.Range(0.3f, 0.9f), rng.Range(-1f, 1f)).normalized;
                mb.AddTube(new[] { st, st + d * 1.2f * s, st + d * 2.2f * s + Vector3.up * 0.4f }, new[] { 0.14f * s, 0.08f * s, 0.03f * s }, 4, c);
            }
        }

        public static void Stump(MeshBuilder mb, MeshBuilder fol, Vector3 p, float s, Rng rng)
        {
            mb.AddLathe(M(p), new[] { new Vector2(0.9f * s, 0), new Vector2(0.7f * s, 0.3f * s), new Vector2(0.65f * s, 0.9f * s), new Vector2(0.01f, 0.95f * s) }, 10,
                new[] { H("#5A3E28"), H("#6E4C30"), H("#6E4C30"), H("#C9A06A") });
            Fern(fol, p + Vector3.right * 0.8f * s, 0.6f, rng);
        }

        public static void Log(MeshBuilder mb, Vector3 p, Rng rng)
        {
            Quaternion q = Quaternion.Euler(0, rng.Range(0, 360f), 90);
            mb.AddLathe(M(p + Vector3.up * 0.4f, q, Vector3.one), new[] { new Vector2(0.01f, -1.8f), new Vector2(0.45f, -1.75f), new Vector2(0.5f, 0f), new Vector2(0.42f, 1.75f), new Vector2(0.01f, 1.8f) }, 9,
                new[] { H("#C9A06A"), H("#7A5232"), H("#6A4428"), H("#7A5232"), H("#C9A06A") });
        }

        // ================================================================ rocks & minerals
        public static void Rock(MeshBuilder mb, Vector3 pos, float size, Color col, Color top, Rng rng)
        {
            var m = M(pos, Quaternion.Euler(rng.Range(-8, 8), rng.Range(0, 360), rng.Range(-8, 8)),
                new Vector3(rng.Range(0.9f, 1.4f), rng.Range(0.65f, 1.0f), rng.Range(0.9f, 1.3f)));
            OrganicProps.Rock(mb, m, size, col, top, rng.Range(0, 100000));
        }

        public static void LavaRock(MeshBuilder mb, MeshBuilder glow, Vector3 p, float size, ZoneStyle z, Rng rng)
        {
            Rock(mb, p, size, z.Cliff, z.TerrainHigh, rng);
            // glowing cracks
            for (int k = 0; k < 3; k++)
            {
                float a = rng.Range(0, Mathf.PI * 2f);
                Vector3 d = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
                Vector3 b = p + d * size * 0.85f + Vector3.up * size * 0.2f;
                glow.AddTube(new[] { b, b + Vector3.up * size * 0.4f + d * 0.2f, b + Vector3.up * size * 0.7f }, new[] { 0.09f, 0.07f, 0.02f }, 4, H("#FF7A1A"), H("#FFD040"));
            }
        }

        public static void LavaPool(MeshBuilder glow, MeshBuilder mb, Vector3 p, float r, Rng rng)
        {
            glow.AddCylinder(M(p + Vector3.up * 0.05f), r, r * 0.95f, 0.08f, 14, H("#FF5A10"), true, true, H("#FFB030"));
            for (int k = 0; k < 7; k++)
            {
                float a = k / 7f * Mathf.PI * 2f;
                // rim boulders stand on the pool bed (shallow) and break through the surface
                Vector3 rp = p + new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * r * 1.05f - Vector3.up * 0.9f;
                mb.AddNaturalRock(M(rp, Quaternion.Euler(0, rng.Range(0, 360f), 0), new Vector3(1.3f, 0.9f, 1f)), rng.Range(0.8f, 1.3f), H("#2A2220"), H("#4A3C36"), rng, 1, 0.3f);
            }
        }

        public static void Obsidian(MeshBuilder mb, Vector3 p, float s, Rng rng)
        {
            int n = rng.Range(2, 5);
            for (int i = 0; i < n; i++)
            {
                Quaternion q = Quaternion.Euler(rng.Range(-25, 25), rng.Range(0, 360), rng.Range(-25, 25));
                float h = rng.Range(1.8f, 3.6f) * s;
                mb.AddCylinder(M(p, q, Vector3.one), 0.5f * s, 0.05f, h, 5, H("#1C1824"), false, false, H("#4A3C6A"));
            }
        }

        public static void IceCrystal(MeshBuilder mb, MeshBuilder glow, Vector3 pos, float s, Rng rng)
        {
            Color a = H("#8FDCFF"), b = H("#E8FBFF");
            int n = rng.Range(3, 6);
            for (int i = 0; i < n; i++)
            {
                Quaternion q = Quaternion.Euler(rng.Range(-28, 28), rng.Range(0, 360), rng.Range(-28, 28));
                float h = rng.Range(2f, 4.5f) * s;
                float w = rng.Range(0.4f, 0.65f) * s;
                mb.AddCylinder(M(pos, q, Vector3.one), w, w * 0.9f, h, 6, a * 0.85f, false, false, a);
                mb.AddCone(M(pos + q * Vector3.up * h, q, Vector3.one), w * 0.9f, w * 1.8f, 6, a, b);
            }
            glow.AddSphere(M(pos + Vector3.up * 0.3f), 0.5f * s, 4, 6, H("#9FE8FF") * 0.6f);
        }

        public static void Mesa(MeshBuilder mb, Vector3 pos, float radius, float height, ZoneStyle z, Rng rng)
        {
            OrganicProps.Butte(mb, pos, radius, height, z.Cliff, Color.Lerp(z.TerrainLow, z.TerrainHigh, 0.5f), z.TerrainHigh, rng.Range(0.75f, 1f), rng.Range(0, 100000));
        }

        public static void VolcanoCone(MeshBuilder mb, MeshBuilder glow, Vector3 pos, float r, ZoneStyle z, Rng rng)
        {
            float h = r * 1.9f;
            var sdf = OrganicProps.Volcano(mb, pos, r, h, z.TerrainLow, z.TerrainMid, z.Cliff, H("#3A1A10"), rng.Range(0, 100000));
            glow.AddCylinder(M(pos + Vector3.up * (h - r * 0.1f)), r * 0.19f, r * 0.19f, 0.2f, 16, H("#FF6A10"), true, true, H("#FFC040"));
            // lava streams follow the sculpted flank (each node is found on the surface, then lifted a little)
            for (int k = 0; k < 4; k++)
            {
                float a = rng.Range(0, Mathf.PI * 2f);
                Vector3 d = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
                var path = new Vector3[8]; var rad = new float[8];
                for (int i = 0; i < 8; i++)
                {
                    float t = i / 7f;
                    float y = Mathf.Lerp(h - r * 0.12f, h * 0.18f, t);
                    path[i] = pos + Sculpt.Hit(sdf, new Vector3(0, y, 0), d, r * 1.6f) + Vector3.up * 0.25f;
                    rad[i] = Mathf.Lerp(0.6f, 1.3f, t);
                }
                glow.AddTube(path, rad, 5, H("#FF6A10"), H("#FF3A08"));
            }
        }

        // ================================================================ man-made
        public static void TikiHut(MeshBuilder mb, MeshBuilder fol, Vector3 pos, float yaw, float s)
        {
            Quaternion q = Quaternion.Euler(0, yaw, 0);
            Color post = H("#7A4E2A"), roof = H("#E3B95C"), roofDark = H("#A87A2C");
            for (int i = 0; i < 4; i++)
            {
                Vector3 o = q * new Vector3((i % 2 == 0 ? -1 : 1) * 1.6f, 0, (i < 2 ? -1 : 1) * 1.6f) * s;
                mb.AddTube(new[] { pos + o, pos + o + Vector3.up * 2.7f * s }, new[] { 0.18f * s, 0.15f * s }, 6, post);
            }
            mb.AddRoundedBox(M(pos + Vector3.up * 0.9f * s, q, Vector3.one), new Vector3(3.8f, 0.25f, 3.8f) * s, 0.08f * s, H("#9A6A3A"), 1);
            // layered thatch
            mb.AddLathe(M(pos + Vector3.up * 2.4f * s, q * Quaternion.Euler(0, 45, 0), Vector3.one),
                new[] { new Vector2(3.4f * s, 0), new Vector2(3.2f * s, 0.25f * s), new Vector2(2.2f * s, 0.9f * s), new Vector2(2.0f * s, 1.05f * s), new Vector2(0.9f * s, 1.9f * s), new Vector2(0.05f, 2.5f * s) }, 4,
                new[] { roofDark, roof, roof * 0.9f, roof, roof * 1.05f, roofDark });
        }

        public static void Torch(MeshBuilder mb, MeshBuilder glow, Vector3 pos, float s)
        {
            mb.AddTube(new[] { pos, pos + Vector3.up * 2.5f * s }, new[] { 0.12f * s, 0.09f * s }, 5, H("#6B4426"));
            mb.AddLathe(M(pos + Vector3.up * 2.4f * s), new[] { new Vector2(0.12f * s, 0), new Vector2(0.32f * s, 0.3f * s), new Vector2(0.3f * s, 0.42f * s) }, 7, new[] { H("#3A2A1A"), H("#4A3422"), H("#2A1E14") });
            glow.AddCone(M(pos + Vector3.up * 2.75f * s), 0.26f * s, 0.85f * s, 7, H("#FF6A1A"), H("#FFE24A"));
        }

        public static void Lantern(MeshBuilder mb, MeshBuilder glow, Vector3 pos, float s)
        {
            mb.AddTube(new[] { pos, pos + Vector3.up * 3f * s, pos + Vector3.up * 3.2f * s + Vector3.right * 0.8f * s }, new[] { 0.1f * s, 0.08f * s, 0.05f * s }, 5, H("#2E2A2A"));
            glow.AddRoundedBox(M(pos + Vector3.up * 2.75f * s + Vector3.right * 0.8f * s), new Vector3(0.35f, 0.5f, 0.35f) * s, 0.08f, H("#FFD27A"), 1);
        }

        public static void Column(MeshBuilder mb, MeshBuilder fol, Vector3 p, float s, ZoneStyle z, Rng rng)
        {
            float h = rng.Range(3f, 6.5f) * s;
            Color st = rng.Jitter(z.WallA, 0.04f);
            mb.AddRoundedBox(M(p + Vector3.up * 0.3f * s), new Vector3(1.8f, 0.6f, 1.8f) * s, 0.1f, st * 0.9f, 1);
            mb.AddLathe(M(p + Vector3.up * 0.6f * s, Quaternion.Euler(rng.Range(-4, 4), 0, rng.Range(-4, 4)), Vector3.one),
                new[] { new Vector2(0.75f * s, 0), new Vector2(0.62f * s, 0.4f * s), new Vector2(0.6f * s, h * 0.5f), new Vector2(0.58f * s, h - 0.3f), new Vector2(0.5f * s, h) }, 10,
                new[] { st, st * 0.95f, st, st * 0.92f, st * 0.85f });
            if (rng.Chance(0.4f)) mb.AddRoundedBox(M(p + Vector3.up * (h + 0.9f) * 1f, Quaternion.Euler(0, rng.Range(0, 90f), 0), Vector3.one), new Vector3(1.9f, 0.5f, 1.9f) * s, 0.1f, st, 1);
            // creeping vines
            fol.AddFrond(p + Vector3.up * h * 0.9f + Vector3.right * 0.62f * s, Vector3.down, Vector3.forward, h * 0.7f, 0.6f, 0f, U0(CellVine), U1(CellVine), H("#3E8A34"), 3);
        }

        public static void Ruins(MeshBuilder mb, MeshBuilder fol, Vector3 p, ZoneStyle z, Rng rng)
        {
            int n = rng.Range(3, 7);
            for (int i = 0; i < n; i++)
            {
                Vector3 o = new Vector3(rng.Range(-2.5f, 2.5f), 0, rng.Range(-2.5f, 2.5f));
                Vector3 sz = new Vector3(rng.Range(1f, 2.2f), rng.Range(0.6f, 1.3f), rng.Range(1f, 1.8f));
                mb.AddRoundedBox(M(p + o + Vector3.up * sz.y * 0.4f, Quaternion.Euler(rng.Range(-8, 8), rng.Range(0, 90), rng.Range(-8, 8)), Vector3.one), sz, 0.12f, rng.Jitter(z.WallA, 0.05f), 1, Color.Lerp(z.WallA, H("#5E8A3C"), 0.4f));
            }
            Grass(fol, p, 1.2f, H("#6DA845"), rng);
        }

        public static void StoneHead(MeshBuilder mb, MeshBuilder fol, Vector3 p, float yaw, float s, ZoneStyle z)
        {
            Quaternion q = Quaternion.Euler(0, yaw, 0);
            Color st = z.WallA, dk = z.WallA * 0.7f;
            mb.AddRoundedBox(M(p + Vector3.up * 1.6f * s, q, Vector3.one), new Vector3(2.4f, 3.2f, 2.2f) * s, 0.5f * s, st, 2, st * 1.05f);
            Vector3 f = q * Vector3.forward, r = q * Vector3.right;
            // brow, eyes, nose, mouth
            mb.AddRoundedBox(M(p + Vector3.up * 2.4f * s + f * 1.05f * s, q, Vector3.one), new Vector3(2.0f, 0.35f, 0.4f) * s, 0.1f * s, st * 0.95f, 1);
            for (int e = -1; e <= 1; e += 2)
                mb.AddRoundedBox(M(p + Vector3.up * 2.05f * s + f * 1.08f * s + r * e * 0.5f * s, q, Vector3.one), new Vector3(0.6f, 0.35f, 0.15f) * s, 0.08f * s, dk, 1);
            mb.AddRoundedBox(M(p + Vector3.up * 1.55f * s + f * 1.15f * s, q, Vector3.one), new Vector3(0.55f, 0.9f, 0.5f) * s, 0.15f * s, st, 1);
            mb.AddRoundedBox(M(p + Vector3.up * 0.85f * s + f * 1.08f * s, q, Vector3.one), new Vector3(1.4f, 0.28f, 0.2f) * s, 0.06f * s, dk, 1);
            fol.AddFrond(p + Vector3.up * 3.1f * s + r * 0.9f * s, Vector3.down, f, 2.2f * s, 0.6f, 0f, U0(CellVine), U1(CellVine), H("#3E8A34"), 3);
        }

        public static void Pyramid(MeshBuilder mb, MeshBuilder fol, Vector3 p, float size, ZoneStyle z, Rng rng)
        {
            int steps = 6;
            for (int i = 0; i < steps; i++)
            {
                float w = size * (1f - i / (float)steps * 0.85f);
                Color c = rng.Jitter(i % 2 == 0 ? z.WallA : z.WallB, 0.03f);
                mb.AddRoundedBox(M(p + Vector3.up * (i * 2.2f + 1.1f)), new Vector3(w, 2.2f, w), 0.3f, c, 1, Color.Lerp(c, H("#5E8A3C"), 0.35f));
            }
            mb.AddRoundedBox(M(p + Vector3.up * (steps * 2.2f + 1.8f)), new Vector3(size * 0.2f, 3f, size * 0.2f), 0.3f, z.WallB, 1);
            for (int k = 0; k < 6; k++)
            {
                float a = rng.Range(0, Mathf.PI * 2f);
                Bush(fol, p + new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * size * 0.45f + Vector3.up * rng.Range(1f, 6f), 1.4f, H("#3E8A34"), rng);
            }
        }

        public static void Cactus(MeshBuilder mb, Vector3 pos, float s, Rng rng)
        {
            Color g = H("#3E9A4A"), g2 = H("#5FC069");
            float h = rng.Range(3.5f, 5.5f) * s;
            // ribbed body growing out of a flared foot, arms that elbow up out of it (one smooth skin each)
            var body = new[] { pos - Vector3.up * 0.2f, pos + Vector3.up * h * 0.3f, pos + Vector3.up * h * 0.65f, pos + Vector3.up * (h - 0.35f * s) };
            OrganicProps.RibbedTube(mb, body, new[] { 0.5f * s, 0.46f * s, 0.44f * s, 0.38f * s }, 9, 0.16f, g, g2);
            int arms = rng.Range(1, 3);
            for (int a = 0; a < arms; a++)
            {
                float side = a == 0 ? 1 : -1;
                float ay = h * rng.Range(0.35f, 0.6f);
                Quaternion yaw = Quaternion.Euler(0, rng.Range(0, 360), 0);
                Vector3 dir = yaw * new Vector3(side, 0, 0);
                float ah = rng.Range(1.0f, 1.8f) * s;
                var path = new[] { pos + Vector3.up * ay, pos + Vector3.up * ay + dir * 0.75f * s, pos + Vector3.up * (ay + 0.3f * s) + dir * 1.05f * s,
                                   pos + Vector3.up * (ay + 0.8f * s) + dir * 1.15f * s, pos + Vector3.up * (ay + ah) + dir * 1.15f * s };
                OrganicProps.RibbedTube(mb, path, new[] { 0.3f * s, 0.29f * s, 0.28f * s, 0.27f * s, 0.24f * s }, 7, 0.16f, g, g2, 12);
            }
        }

        public static void SignPost(MeshBuilder mb, Vector3 p, float yaw)
        {
            Quaternion q = Quaternion.Euler(0, yaw, 0);
            mb.AddTube(new[] { p, p + Vector3.up * 2.6f }, new[] { 0.1f, 0.09f }, 5, H("#6E4A2C"));
            mb.AddRoundedBox(M(p + Vector3.up * 2.2f + q * Vector3.right * 0.5f, q * Quaternion.Euler(0, 0, 4), Vector3.one), new Vector3(1.4f, 0.4f, 0.08f), 0.04f, H("#B98A58"), 1);
        }

        public static void MineCart(MeshBuilder mb, Vector3 p, float yaw)
        {
            Quaternion q = Quaternion.Euler(0, yaw, 0);
            mb.AddRoundedBox(M(p + Vector3.up * 1.0f, q, Vector3.one), new Vector3(1.6f, 1.0f, 2.2f), 0.12f, H("#6A5A4A"), 2);
            mb.AddRoundedBox(M(p + Vector3.up * 1.45f, q, Vector3.one), new Vector3(1.4f, 0.2f, 2.0f), 0.1f, H("#B07A3A"), 1); // ore load
            for (int i = 0; i < 4; i++)
            {
                Vector3 o = q * new Vector3(i % 2 == 0 ? -0.82f : 0.82f, 0.38f, i < 2 ? -0.7f : 0.7f);
                mb.AddCylinder(M(p + o, q * Quaternion.Euler(0, 0, 90), Vector3.one), 0.36f, 0.36f, 0.14f, 10, H("#2A2A2E"));
            }
        }

        public static void Barrels(MeshBuilder mb, Vector3 p, Rng rng)
        {
            int n = rng.Range(1, 4);
            for (int i = 0; i < n; i++)
            {
                Vector3 o = new Vector3(rng.Range(-1f, 1f), 0, rng.Range(-1f, 1f));
                mb.AddLathe(M(p + o), new[] { new Vector2(0.45f, 0), new Vector2(0.55f, 0.6f), new Vector2(0.45f, 1.2f), new Vector2(0.01f, 1.21f) }, 10,
                    new[] { H("#7A4E2A"), H("#9A6A3A"), H("#7A4E2A"), H("#6A4224") });
                mb.AddTorus(M(p + o + Vector3.up * 0.3f), 0.52f, 0.03f, 10, 3, H("#3A3A3E"));
                mb.AddTorus(M(p + o + Vector3.up * 0.9f), 0.52f, 0.03f, 10, 3, H("#3A3A3E"));
            }
        }

        public static void CrateStack(MeshBuilder mb, Vector3 p, Rng rng)
        {
            int n = rng.Range(1, 4);
            for (int i = 0; i < n; i++)
            {
                float sz = rng.Range(0.8f, 1.2f);
                Vector3 o = new Vector3(rng.Range(-0.8f, 0.8f), sz * 0.5f + (i == 2 ? 1f : 0f), rng.Range(-0.8f, 0.8f));
                mb.AddRoundedBox(M(p + o, Quaternion.Euler(0, rng.Range(0, 90), 0), Vector3.one), Vector3.one * sz, 0.05f, rng.Jitter(H("#B98A50"), 0.05f), 1);
            }
        }

        public static void Cabin(MeshBuilder mb, MeshBuilder glow, Vector3 p, float yaw, float s, Rng rng)
        {
            Quaternion q = Quaternion.Euler(0, yaw, 0);
            Color wood = H("#8A5A36"), roof = H("#A8322A"), snow = H("#F6FAFF");
            mb.AddRoundedBox(M(p + Vector3.up * 1.4f * s, q, Vector3.one), new Vector3(4f, 2.8f, 3.4f) * s, 0.12f * s, wood, 1);
            // log ends texture-free: stacked horizontal grooves
            for (int i = 0; i < 5; i++)
                mb.AddRoundedBox(M(p + Vector3.up * (0.35f + i * 0.55f) * s + q * Vector3.forward * 1.71f * s, q, Vector3.one), new Vector3(4.1f, 0.12f, 0.04f) * s, 0.02f, wood * 0.75f, 1);
            // gable roof (two slabs) with snow
            for (int side = -1; side <= 1; side += 2)
            {
                Quaternion rq = q * Quaternion.Euler(0, 0, side * 35f);
                Vector3 c = p + Vector3.up * 3.55f * s + q * Vector3.right * side * 1.05f * s;
                mb.AddRoundedBox(M(c, rq, Vector3.one), new Vector3(2.7f, 0.25f, 4.0f) * s, 0.08f, roof, 1, snow);
            }
            mb.AddRoundedBox(M(p + Vector3.up * 4.4f * s + q * new Vector3(1.0f, 0, -0.8f) * s, q, Vector3.one), new Vector3(0.6f, 1.4f, 0.6f) * s, 0.06f, H("#5A5A62"), 1, snow);
            glow.AddRoundedBox(M(p + Vector3.up * 1.5f * s + q * Vector3.forward * 1.72f * s, q, Vector3.one), new Vector3(0.9f, 0.8f, 0.05f) * s, 0.04f, H("#FFC86A"), 1);
        }

        public static void Snowman(MeshBuilder mb, Vector3 pos, float yaw, float s)
        {
            Color w = H("#FBFDFF");
            mb.AddSphere(M(pos + Vector3.up * 1.0f * s), 1.0f * s, 10, 14, w, H("#D6E4F5"));
            mb.AddSphere(M(pos + Vector3.up * 2.4f * s), 0.72f * s, 10, 14, w);
            mb.AddSphere(M(pos + Vector3.up * 3.4f * s), 0.5f * s, 10, 14, w);
            Quaternion q = Quaternion.Euler(0, yaw, 0);
            mb.AddCone(M(pos + Vector3.up * 3.4f * s + q * Vector3.forward * 0.45f * s, q * Quaternion.Euler(90, 0, 0), Vector3.one), 0.1f * s, 0.6f * s, 7, H("#FF8A1E"), H("#FF8A1E"));
            mb.AddLathe(M(pos + Vector3.up * 3.78f * s), new[] { new Vector2(0.48f * s, 0), new Vector2(0.48f * s, 0.06f * s), new Vector2(0.3f * s, 0.07f * s), new Vector2(0.3f * s, 0.6f * s), new Vector2(0.01f, 0.61f * s) }, 10,
                new[] { H("#222233"), H("#222233"), H("#222233"), H("#2A2A3E"), H("#2A2A3E") });
            mb.AddTorus(M(pos + Vector3.up * 2.95f * s), 0.55f * s, 0.12f * s, 12, 5, H("#E8322A"));
            for (int e = -1; e <= 1; e += 2)
                mb.AddSphere(M(pos + Vector3.up * 3.55f * s + q * new Vector3(e * 0.18f, 0, 0.42f) * s), 0.07f * s, 4, 6, H("#111111"));
        }

        public static void Igloo(MeshBuilder mb, Vector3 pos, float yaw, float s)
        {
            Color w = H("#EAF4FF");
            mb.AddSphere(M(pos, Quaternion.identity, new Vector3(1, 0.85f, 1)), 3f * s, 10, 16, w, w);
            Quaternion q = Quaternion.Euler(0, yaw, 0);
            mb.AddRoundedBox(M(pos + q * new Vector3(0, 0.9f, 3.0f) * s, q, Vector3.one), new Vector3(1.6f, 1.8f, 1.4f) * s, 0.25f * s, H("#D5E6F8"), 2);
            mb.AddRoundedBox(M(pos + q * new Vector3(0, 0.8f, 3.72f) * s, q, Vector3.one), new Vector3(1.0f, 1.4f, 0.05f) * s, 0.02f, H("#2A3550"), 1);
        }

        public static void Cloud(MeshBuilder mb, Vector3 pos, float s, Rng rng)
        {
            Color w = new Color(1, 1, 1, 1), shade = H("#DCE8F6");
            int n = rng.Range(4, 8);
            for (int i = 0; i < n; i++)
            {
                Vector3 o = new Vector3(rng.Range(-1.8f, 1.8f), rng.Range(-0.2f, 0.5f), rng.Range(-0.8f, 0.8f)) * s;
                float r = rng.Range(0.7f, 1.4f) * s;
                mb.AddSphere(M(pos + o, Quaternion.identity, new Vector3(1.3f, 0.75f, 1f)), r, 8, 12, w, shade);
            }
        }

        // ================================================================ pickups
        public static Mesh CrateMesh(float size)
        {
            var mb = new MeshBuilder();
            mb.AddBox(Matrix4x4.identity, Vector3.one * size, Color.white);
            return mb.ToMesh("Crate");
        }

        public static Mesh FruitMesh()
        {
            var mb = new MeshBuilder();
            Color a = H("#FF5A2A"), b = H("#FFB02E");
            mb.AddSphere(Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(1f, 0.9f, 0.85f)), 0.45f, 10, 14, b, a);
            mb.AddTube(new[] { new Vector3(0, 0.34f, 0), new Vector3(0.04f, 0.5f, 0), new Vector3(0.09f, 0.58f, 0) }, new[] { 0.05f, 0.04f, 0.03f }, 5, H("#5A3A1E"));
            mb.AddSphere(Matrix4x4.TRS(new Vector3(0.2f, 0.55f, 0), Quaternion.Euler(0, 0, -40), new Vector3(1.4f, 0.3f, 0.7f)), 0.18f, 5, 8, H("#3FBF3A"));
            return mb.ToMesh("Fruit");
        }
    }
}
