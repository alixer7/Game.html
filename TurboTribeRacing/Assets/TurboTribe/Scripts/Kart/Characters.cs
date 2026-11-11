using UnityEngine;

namespace TurboTribe
{
    public enum KartClass { Balanced, Speed, Acceleration, Turning }
    public enum HeadStyle { Fox, Bear, Rabbit, Croc, Penguin, Raccoon, Tiger, Yeti }

    /// <summary>Kart handling numbers. Four classes, like CTR's Balanced / Speed / Acceleration / Turning.</summary>
    public struct KartStats
    {
        public float MaxSpeed;     // m/s
        public float Accel;        // m/s^2 at low speed
        public float TurnRate;     // deg/s at full lock
        public float SlideMin;     // deg/s when counter-steering in a slide (wide)
        public float SlideMax;     // deg/s when steering into a slide (tight)

        public static KartStats For(KartClass c)
        {
            switch (c)
            {
                case KartClass.Speed: return new KartStats { MaxSpeed = 29.8f, Accel = 18.5f, TurnRate = 96f, SlideMin = 24f, SlideMax = 64f };
                case KartClass.Acceleration: return new KartStats { MaxSpeed = 27.6f, Accel = 29f, TurnRate = 102f, SlideMin = 26f, SlideMax = 70f };
                case KartClass.Turning: return new KartStats { MaxSpeed = 27.9f, Accel = 22f, TurnRate = 116f, SlideMin = 30f, SlideMax = 80f };
                default: return new KartStats { MaxSpeed = 28.5f, Accel = 22f, TurnRate = 104f, SlideMin = 26f, SlideMax = 70f };
            }
        }

        // 0..1 ratings for the character select bars
        public float SpeedRating { get { return Mathf.InverseLerp(26.8f, 30.2f, MaxSpeed); } }
        public float AccelRating { get { return Mathf.InverseLerp(15f, 30f, Accel); } }
        public float TurnRating { get { return Mathf.InverseLerp(88f, 120f, TurnRate); } }
    }

    public class CharacterDef
    {
        public string Name;
        public string Tagline;
        public KartClass Class;
        public HeadStyle Style;
        public Color Fur, FurLight, Kart, KartAccent, Shirt;

        static Color H(string hex) { Color c; ColorUtility.TryParseHtmlString(hex, out c); return c; }

        public static readonly CharacterDef[] All =
        {
            new CharacterDef { Name = "BLAZE", Tagline = "Fox with fire in the tank", Class = KartClass.Balanced, Style = HeadStyle.Fox,
                Fur = H("#F2711C"), FurLight = H("#FFF1DE"), Kart = H("#E8262B"), KartAccent = H("#FFD23F"), Shirt = H("#2B6CE8") },
            new CharacterDef { Name = "BRUNO", Tagline = "Big bear, bigger top speed", Class = KartClass.Speed, Style = HeadStyle.Bear,
                Fur = H("#8A5A34"), FurLight = H("#E3C49B"), Kart = H("#2E7D32"), KartAccent = H("#F2F2F2"), Shirt = H("#E53935") },
            new CharacterDef { Name = "PIPPA", Tagline = "Quickest off the line", Class = KartClass.Acceleration, Style = HeadStyle.Rabbit,
                Fur = H("#F4EEF6"), FurLight = H("#FF9EC4"), Kart = H("#FF4FA3"), KartAccent = H("#7C4DFF"), Shirt = H("#FFE15A") },
            new CharacterDef { Name = "TOTO", Tagline = "Corners like a dream", Class = KartClass.Turning, Style = HeadStyle.Croc,
                Fur = H("#58B947"), FurLight = H("#D8F0A8"), Kart = H("#FFB300"), KartAccent = H("#2A2A2A"), Shirt = H("#8E24AA") },
            new CharacterDef { Name = "KIKO", Tagline = "Ice-cool and nimble", Class = KartClass.Acceleration, Style = HeadStyle.Penguin,
                Fur = H("#26283A"), FurLight = H("#FFFFFF"), Kart = H("#1E88E5"), KartAccent = H("#FF7043"), Shirt = H("#FF7043") },
            new CharacterDef { Name = "RAZZ", Tagline = "Sneaky lines, sharp turns", Class = KartClass.Turning, Style = HeadStyle.Raccoon,
                Fur = H("#8C8FA0"), FurLight = H("#E9EAF0"), Kart = H("#7E57C2"), KartAccent = H("#00E5A0"), Shirt = H("#37474F") },
            new CharacterDef { Name = "MAMBO", Tagline = "All roar, all speed", Class = KartClass.Speed, Style = HeadStyle.Tiger,
                Fur = H("#FF9A2E"), FurLight = H("#FFF3E0"), Kart = H("#212121"), KartAccent = H("#FF6D00"), Shirt = H("#43A047") },
            new CharacterDef { Name = "NOVA", Tagline = "Snow-white all-rounder", Class = KartClass.Balanced, Style = HeadStyle.Yeti,
                Fur = H("#F5F8FF"), FurLight = H("#8EC9FF"), Kart = H("#00ACC1"), KartAccent = H("#FFFFFF"), Shirt = H("#3949AB") },
        };

        public KartStats Stats { get { return KartStats.For(Class); } }

        public static string ClassName(KartClass c)
        {
            switch (c)
            {
                case KartClass.Speed: return "SPEED";
                case KartClass.Acceleration: return "ACCEL";
                case KartClass.Turning: return "TURNING";
                default: return "BALANCED";
            }
        }
    }
}
