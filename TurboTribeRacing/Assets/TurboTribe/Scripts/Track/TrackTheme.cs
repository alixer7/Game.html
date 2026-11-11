using UnityEngine;

namespace TurboTribe
{
    public enum ThemeKind { Beach, Canyon, Snow }
    public enum WallKind { Fence, Stone, Bamboo, Rail, Snowbank, Ice, Timber }
    public enum DecorSet { Beach, Jungle, Temple, Volcano, Desert, Mine, Mesa, River, Village, IceCave, Lake, Alpine }

    /// <summary>Sky, light, fog and water for a whole track.</summary>
    public class TrackTheme
    {
        public ThemeKind Kind;
        public Color SkyTop, SkyHorizon, SkyBottom, Fog, Sun, AmbSky, AmbGround;
        public Vector3 SunEuler;
        public float FogStart, FogEnd;
        public Color WaterShallow, WaterDeep;
        public bool HasWater;
        public int MusicSeed;
        public float MusicTempo;
        // legacy palette (menu island / fallbacks)
        public Color TerrainLow, TerrainMid, TerrainHigh, Cliff;

        static Color H(string hex) { Color c; ColorUtility.TryParseHtmlString(hex, out c); return c; }

        public static TrackTheme Get(string id)
        {
            switch (id)
            {
                case "canyon": return Canyon();
                case "snow": return Snow();
                default: return Beach();
            }
        }

        public static TrackTheme Beach()
        {
            return new TrackTheme
            {
                Kind = ThemeKind.Beach,
                SkyTop = H("#2C86EE"), SkyHorizon = H("#B4E8FF"), SkyBottom = H("#E9FBFF"), Fog = H("#C4ECFF"),
                Sun = H("#FFF0D2"), SunEuler = new Vector3(46, -35, 0), AmbSky = H("#86B1D2"), AmbGround = H("#8F7B5C"),
                FogStart = 140, FogEnd = 620,
                WaterShallow = H("#3FE6D8"), WaterDeep = H("#0A5FC4"), HasWater = true,
                MusicSeed = 3, MusicTempo = 142,
                TerrainLow = H("#F3DDA2"), TerrainMid = H("#59C24A"), TerrainHigh = H("#3E9A3A"), Cliff = H("#A07A5A")
            };
        }

        public static TrackTheme Canyon()
        {
            return new TrackTheme
            {
                Kind = ThemeKind.Canyon,
                SkyTop = H("#3576D6"), SkyHorizon = H("#FFD7A6"), SkyBottom = H("#FFE8C8"), Fog = H("#F4CFA6"),
                Sun = H("#FFE4BA"), SunEuler = new Vector3(38, 60, 0), AmbSky = H("#A0A8C4"), AmbGround = H("#A35C3C"),
                FogStart = 160, FogEnd = 700,
                WaterShallow = H("#56C8BC"), WaterDeep = H("#24607A"), HasWater = true,
                MusicSeed = 11, MusicTempo = 148,
                TerrainLow = H("#D98B4E"), TerrainMid = H("#C2643A"), TerrainHigh = H("#E8A86A"), Cliff = H("#A84B2A")
            };
        }

        public static TrackTheme Snow()
        {
            return new TrackTheme
            {
                Kind = ThemeKind.Snow,
                SkyTop = H("#3A5DB6"), SkyHorizon = H("#D2E5FF"), SkyBottom = H("#F2F8FF"), Fog = H("#DEECFF"),
                Sun = H("#FFF4E6"), SunEuler = new Vector3(30, 150, 0), AmbSky = H("#A9BBE2"), AmbGround = H("#7F8FB0"),
                FogStart = 120, FogEnd = 600,
                WaterShallow = H("#93E6FF"), WaterDeep = H("#2A6CB5"), HasWater = true,
                MusicSeed = 23, MusicTempo = 152,
                TerrainLow = H("#F4F8FF"), TerrainMid = H("#E2EAF7"), TerrainHigh = H("#FFFFFF"), Cliff = H("#7C88A6")
            };
        }
    }

    /// <summary>Local look of a stretch of road: surface, curbs, walls, ground and decoration set.</summary>
    public class ZoneStyle
    {
        public string Id;
        public Color Road, RoadEdge, CurbA, CurbB, Shoulder, WallA, WallB, WallTop, Underside;
        public Color TerrainLow, TerrainMid, TerrainHigh, Cliff;
        public WallKind Wall;
        public DecorSet Decor;
        public float WallHeight = 1.3f;
        public float Natural;   // terrain character: 0 flat island, 1 canyon cliffs, 2 mountains
        public float DecorDensity = 1f;

        static Color H(string hex) { Color c; ColorUtility.TryParseHtmlString(hex, out c); return c; }

        public static ZoneStyle Get(string id)
        {
            switch (id)
            {
                case "jungle":
                    return new ZoneStyle { Id = id, Road = H("#B98A5A"), RoadEdge = H("#7E5A36"), CurbA = H("#2FAE4A"), CurbB = H("#F5E6B0"), Shoulder = H("#4E9A35"),
                        WallA = H("#8FB24A"), WallB = H("#6E9436"), WallTop = H("#B6CF6A"), Underside = H("#4A3220"), TerrainLow = H("#5EA83E"), TerrainMid = H("#3F8A34"),
                        TerrainHigh = H("#2E6E2C"), Cliff = H("#6B5A44"), Wall = WallKind.Bamboo, Decor = DecorSet.Jungle, DecorDensity = 1.6f };
                case "temple":
                    return new ZoneStyle { Id = id, Road = H("#C9B48C"), RoadEdge = H("#8C7A58"), CurbA = H("#D9A43A"), CurbB = H("#5A4A3A"), Shoulder = H("#6E9A48"),
                        WallA = H("#A89A82"), WallB = H("#8E816C"), WallTop = H("#C2B49A"), Underside = H("#4E4538"), TerrainLow = H("#7FA650"), TerrainMid = H("#5C8A3C"),
                        TerrainHigh = H("#4A7432"), Cliff = H("#8C826E"), Wall = WallKind.Stone, Decor = DecorSet.Temple, WallHeight = 1.5f };
                case "volcano":
                    return new ZoneStyle { Id = id, Road = H("#5C4A44"), RoadEdge = H("#3A2C28"), CurbA = H("#FF6A1A"), CurbB = H("#2A2224"), Shoulder = H("#3C302C"),
                        WallA = H("#4A3A36"), WallB = H("#3A2C2A"), WallTop = H("#6A524A"), Underside = H("#2A1E1C"), TerrainLow = H("#4A3C38"), TerrainMid = H("#3A2E2C"),
                        TerrainHigh = H("#5A4A44"), Cliff = H("#2C2220"), Wall = WallKind.Stone, Decor = DecorSet.Volcano, WallHeight = 1.5f, Natural = 0.35f };
                case "desert":
                    return new ZoneStyle { Id = id, Road = H("#D29458"), RoadEdge = H("#A2643A"), CurbA = H("#FFD23F"), CurbB = H("#E23A28"), Shoulder = H("#E2B077"),
                        WallA = H("#B5532F"), WallB = H("#8E3E22"), WallTop = H("#D8834F"), Underside = H("#5E2E1A"), TerrainLow = H("#E2A262"), TerrainMid = H("#C8703F"),
                        TerrainHigh = H("#EAB27A"), Cliff = H("#A84B2A"), Wall = WallKind.Timber, Decor = DecorSet.Desert, Natural = 1f };
                case "mine":
                    return new ZoneStyle { Id = id, Road = H("#6E5A4A"), RoadEdge = H("#46382E"), CurbA = H("#FFC21A"), CurbB = H("#2A2A2E"), Shoulder = H("#5A4A3E"),
                        WallA = H("#8A6A44"), WallB = H("#6A5034"), WallTop = H("#A07E52"), Underside = H("#33261C"), TerrainLow = H("#8A5A3A"), TerrainMid = H("#6E4630"),
                        TerrainHigh = H("#9A6A46"), Cliff = H("#5A3A26"), Wall = WallKind.Rail, Decor = DecorSet.Mine, Natural = 1f };
                case "mesa":
                    return new ZoneStyle { Id = id, Road = H("#C27A48"), RoadEdge = H("#8E5030"), CurbA = H("#F2F2F2"), CurbB = H("#2E8BEF"), Shoulder = H("#D69A62"),
                        WallA = H("#C0603A"), WallB = H("#9C4A2A"), WallTop = H("#E09A62"), Underside = H("#5E2E1A"), TerrainLow = H("#E09A5A"), TerrainMid = H("#C46A3A"),
                        TerrainHigh = H("#F0B67E"), Cliff = H("#B4502C"), Wall = WallKind.Stone, Decor = DecorSet.Mesa, Natural = 1f };
                case "river":
                    return new ZoneStyle { Id = id, Road = H("#B49A78"), RoadEdge = H("#7E6A50"), CurbA = H("#FFFFFF"), CurbB = H("#3A8A5A"), Shoulder = H("#7AA25A"),
                        WallA = H("#9A8A70"), WallB = H("#7E705A"), WallTop = H("#BCAE92"), Underside = H("#4A3E30"), TerrainLow = H("#C8B88E"), TerrainMid = H("#7EA25A"),
                        TerrainHigh = H("#C68A54"), Cliff = H("#9A5A36"), Wall = WallKind.Timber, Decor = DecorSet.River, Natural = 1f };
                case "village":
                    return new ZoneStyle { Id = id, Road = H("#9AA6C2"), RoadEdge = H("#6E7A98"), CurbA = H("#E8322A"), CurbB = H("#FFFFFF"), Shoulder = H("#EEF4FF"),
                        WallA = H("#8A6A4A"), WallB = H("#6E543A"), WallTop = H("#F4F8FF"), Underside = H("#4F5A78"), TerrainLow = H("#F4F8FF"), TerrainMid = H("#E4ECF8"),
                        TerrainHigh = H("#FFFFFF"), Cliff = H("#7C88A6"), Wall = WallKind.Fence, Decor = DecorSet.Village, Natural = 2f };
                case "icecave":
                    return new ZoneStyle { Id = id, Road = H("#8FB8DA"), RoadEdge = H("#5E86AA"), CurbA = H("#2F6BFF"), CurbB = H("#E8F6FF"), Shoulder = H("#BFE2FF"),
                        WallA = H("#A8DCFF"), WallB = H("#86C4F0"), WallTop = H("#E6F6FF"), Underside = H("#3A5A86"), TerrainLow = H("#CFEAFF"), TerrainMid = H("#A8D2F2"),
                        TerrainHigh = H("#E8F6FF"), Cliff = H("#6E9CC8"), Wall = WallKind.Ice, Decor = DecorSet.IceCave, Natural = 2f };
                case "lake":
                    return new ZoneStyle { Id = id, Road = H("#A8C0DA"), RoadEdge = H("#7894B4"), CurbA = H("#FFFFFF"), CurbB = H("#7A5AFF"), Shoulder = H("#E6F0FF"),
                        WallA = H("#E6F2FF"), WallB = H("#C2DAF2"), WallTop = H("#FFFFFF"), Underside = H("#4F5A78"), TerrainLow = H("#F4F8FF"), TerrainMid = H("#E2EAF7"),
                        TerrainHigh = H("#FFFFFF"), Cliff = H("#7C88A6"), Wall = WallKind.Snowbank, Decor = DecorSet.Lake, Natural = 2f };
                case "alpine":
                    return new ZoneStyle { Id = id, Road = H("#AEB8D2"), RoadEdge = H("#7D89A8"), CurbA = H("#2F6BFF"), CurbB = H("#FFFFFF"), Shoulder = H("#F2F6FF"),
                        WallA = H("#E6F2FF"), WallB = H("#B9D6F5"), WallTop = H("#FFFFFF"), Underside = H("#4F5A78"), TerrainLow = H("#F4F8FF"), TerrainMid = H("#E2EAF7"),
                        TerrainHigh = H("#FFFFFF"), Cliff = H("#6F7B98"), Wall = WallKind.Snowbank, Decor = DecorSet.Alpine, Natural = 2f };
                default: // beach
                    return new ZoneStyle { Id = "beach", Road = H("#E2B77A"), RoadEdge = H("#B98A50"), CurbA = H("#F23A2E"), CurbB = H("#FFFFFF"), Shoulder = H("#F2DAA4"),
                        WallA = H("#C98A45"), WallB = H("#A86A30"), WallTop = H("#E7B672"), Underside = H("#6B4A2E"), TerrainLow = H("#F3DDA2"), TerrainMid = H("#59C24A"),
                        TerrainHigh = H("#3E9A3A"), Cliff = H("#A07A5A"), Wall = WallKind.Fence, Decor = DecorSet.Beach };
            }
        }
    }
}
