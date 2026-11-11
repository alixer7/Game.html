using UnityEngine;

namespace TurboTribe
{
    public enum SteerMode { Stick = 0, Buttons = 1, Tilt = 2 }

    /// <summary>Persistent player settings (PlayerPrefs).</summary>
    public static class Settings
    {
        static int I(string k, int d) { return PlayerPrefs.GetInt("tt_" + k, d); }
        static void I(string k, int v, bool save) { PlayerPrefs.SetInt("tt_" + k, v); if (save) PlayerPrefs.Save(); }
        static float GetF(string k, float d) { return PlayerPrefs.GetFloat("tt_" + k, d); }
        static void SetF(string k, float v) { PlayerPrefs.SetFloat("tt_" + k, v); PlayerPrefs.Save(); }

        public static bool AutoGas { get { return I("autogas", 1) == 1; } set { I("autogas", value ? 1 : 0, true); } }
        public static SteerMode Steering { get { return (SteerMode)I("steer", 0); } set { I("steer", (int)value, true); } }
        public static float Sensitivity { get { return GetF("sens", 1f); } set { SetF("sens", Mathf.Clamp(value, 0.5f, 1.6f)); } }
        public static float MusicVolume { get { return GetF("music", 0.6f); } set { SetF("music", Mathf.Clamp01(value)); } }
        public static float SfxVolume { get { return GetF("sfx", 0.9f); } set { SetF("sfx", Mathf.Clamp01(value)); } }
        public static int Quality { get { return I("quality", 1); } set { I("quality", Mathf.Clamp(value, 0, 2), true); } }
        public static bool ShowFps { get { return I("fps", 0) == 1; } set { I("fps", value ? 1 : 0, true); } }
        public static int Difficulty { get { return I("diff", 1); } set { I("diff", Mathf.Clamp(value, 0, 2), true); } }
        public static int Laps { get { return I("laps", 3); } set { I("laps", Mathf.Clamp(value, 1, 7), true); } }
        public static int CharacterIndex { get { return I("char", 0); } set { I("char", value, true); } }
        public static int TrackIndex { get { return I("track", 0); } set { I("track", value, true); } }
        public static bool LeftHanded { get { return I("lefty", 0) == 1; } set { I("lefty", value ? 1 : 0, true); } }

        public static float BestLap(string track) { return GetF("best_" + track, 0f); }
        public static void SetBestLap(string track, float t) { SetF("best_" + track, t); }
        public static int Trophy(string track) { return I("trophy_" + track, 0); }
        public static void SetTrophy(string track, int place) { int cur = Trophy(track); if (cur == 0 || place < cur) I("trophy_" + track, place, true); }

        public static string DifficultyName(int d) { return d == 0 ? "EASY" : d == 2 ? "HARD" : "NORMAL"; }

        public static void ApplyQuality()
        {
            int q = Quality;
            Application.targetFrameRate = q == 0 ? 30 : 60;
            QualitySettings.vSyncCount = 0;
            QualitySettings.antiAliasing = q == 2 ? 4 : (q == 1 ? 2 : 0);
            QualitySettings.shadows = ShadowQuality.Disable;
            float scale = q == 0 ? 0.7f : q == 1 ? 0.85f : 1f;
            // render-scale on high-dpi phones keeps the GPU cool (the game is landscape-only)
            if (Application.isMobilePlatform)
            {
                if (nativeW == 0)
                {
                    nativeW = Mathf.Max(Display.main.systemWidth, Display.main.systemHeight);
                    nativeH = Mathf.Min(Display.main.systemWidth, Display.main.systemHeight);
                }
                if (nativeH <= 0) return;
                int targetH = Mathf.RoundToInt(Mathf.Min(nativeH, 1080) * scale);
                int targetW = Mathf.RoundToInt(targetH * (nativeW / (float)nativeH));
                Screen.SetResolution(targetW, targetH, true);
            }
        }

        static int nativeW, nativeH;
    }
}
