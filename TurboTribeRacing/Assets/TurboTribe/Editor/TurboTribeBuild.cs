using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

namespace TurboTribe.EditorTools
{
    /// <summary>
    /// One-click setup + Android APK build.
    /// Menu: Turbo Tribe / ...   Batch mode: -executeMethod TurboTribe.EditorTools.TurboTribeBuild.BuildAndroidCLI
    /// </summary>
    public static class TurboTribeBuild
    {
        public const string ScenePath = "Assets/Scenes/Main.unity";
        const string DefaultApk = "Builds/Android/TurboTribeRacing.apk";

        [MenuItem("Turbo Tribe/1. Create Main Scene", false, 1)]
        public static void CreateScene()
        {
            if (!File.Exists(ScenePath))
            {
                Directory.CreateDirectory("Assets/Scenes");
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                EditorSceneManager.SaveScene(scene, ScenePath);
                AssetDatabase.Refresh();
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            Debug.Log("[TurboTribe] Main scene ready: " + ScenePath + " (the game boots itself in any scene, just press Play)");
        }

        [MenuItem("Turbo Tribe/2. Configure Android Player", false, 2)]
        public static void ConfigureAndroid()
        {
            var android = NamedBuildTarget.Android;
            PlayerSettings.companyName = "TurboTribe";
            PlayerSettings.productName = "Turbo Tribe Racing";
            PlayerSettings.SetApplicationIdentifier(android, "com.turbotribe.racing");
            PlayerSettings.bundleVersion = "0.3.0";
            PlayerSettings.Android.bundleVersionCode = 3;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.SetScriptingBackend(android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64 | AndroidArchitecture.ARMv7;
            PlayerSettings.Android.minSdkVersion = (AndroidSdkVersions)24;
            PlayerSettings.SetManagedStrippingLevel(android, ManagedStrippingLevel.Low);
            PlayerSettings.colorSpace = ColorSpace.Gamma; // vertex-colour art is authored in gamma
            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[] { GraphicsDeviceType.OpenGLES3, GraphicsDeviceType.Vulkan });
            PlayerSettings.SplashScreen.backgroundColor = new Color(0.106f, 0.082f, 0.188f);
            EditorUserBuildSettings.buildAppBundle = false;
            Debug.Log("[TurboTribe] Android player settings configured (landscape, IL2CPP, ARM64+ARMv7, API 24+).");
        }

        [MenuItem("Turbo Tribe/3. Build Android APK", false, 3)]
        public static void BuildApkMenu()
        {
            string path = EditorUtility.SaveFilePanel("Save APK", "Builds/Android", "TurboTribeRacing", "apk");
            if (string.IsNullOrEmpty(path)) return;
            if (BuildApk(path)) EditorUtility.RevealInFinder(path);
        }

        public static bool BuildApk(string path)
        {
            CreateScene();
            ConfigureAndroid();
            if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.Android)
                EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
            string dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var opts = new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = path,
                target = BuildTarget.Android,
                options = BuildOptions.None
            };
            BuildReport report = BuildPipeline.BuildPlayer(opts);
            bool ok = report.summary.result == BuildResult.Succeeded;
            Debug.Log("[TurboTribe] Build " + (ok ? "SUCCEEDED: " + path : "FAILED: " + report.summary.result) +
                      " (" + (report.summary.totalSize / (1024UL * 1024UL)) + " MB)");
            return ok;
        }

        /// <summary>Command-line / CI entry. Accepts -buildPath, or game-ci's -customBuildPath.</summary>
        public static void BuildAndroidCLI()
        {
            string path = Arg("-buildPath") ?? Arg("-customBuildPath") ?? DefaultApk;
            if (!path.EndsWith(".apk")) path = Path.Combine(path, "TurboTribeRacing.apk");
            bool ok = BuildApk(path);
            EditorApplication.Exit(ok ? 0 : 1);
        }

        static string Arg(string name)
        {
            var args = System.Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++) if (args[i] == name) return args[i + 1];
            return null;
        }
    }

    /// <summary>First time the project opens: create + open the main scene so pressing Play just works.</summary>
    [InitializeOnLoad]
    static class TurboTribeFirstRun
    {
        static TurboTribeFirstRun()
        {
            EditorApplication.delayCall += () =>
            {
                if (Application.isBatchMode || EditorApplication.isPlayingOrWillChangePlaymode) return;
                if (SessionState.GetBool("tt_first_run", false)) return;
                SessionState.SetBool("tt_first_run", true);
                if (!File.Exists(TurboTribeBuild.ScenePath))
                {
                    TurboTribeBuild.CreateScene();
                    TurboTribeBuild.ConfigureAndroid();
                    EditorSceneManager.OpenScene(TurboTribeBuild.ScenePath);
                    Debug.Log("[TurboTribe] Project ready. Press Play to race, or use the 'Turbo Tribe' menu to build the APK.");
                }
            };
        }
    }
}
