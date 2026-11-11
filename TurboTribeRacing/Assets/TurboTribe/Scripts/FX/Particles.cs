using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>Code-configured particle systems (no assets) plus a global one-shot effect pool.</summary>
    public static class Particles
    {
        public static ParticleSystem Create(string name, Transform parent, bool additive, float lifetime, float speed, float size, Color color,
            float rate, float gravity = 0f, bool world = true, float shapeRadius = 0.1f, float shapeAngle = 15f, int maxParticles = 200)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.duration = 1f;
            main.loop = true;
            main.startLifetime = new ParticleSystem.MinMaxCurve(lifetime * 0.7f, lifetime);
            main.startSpeed = new ParticleSystem.MinMaxCurve(speed * 0.6f, speed);
            main.startSize = new ParticleSystem.MinMaxCurve(size * 0.7f, size * 1.2f);
            main.startColor = color;
            main.gravityModifier = gravity;
            main.simulationSpace = world ? ParticleSystemSimulationSpace.World : ParticleSystemSimulationSpace.Local;
            main.maxParticles = maxParticles;
            main.playOnAwake = false;
            main.scalingMode = ParticleSystemScalingMode.Hierarchy;
            var em = ps.emission;
            em.rateOverTime = rate;
            var sh = ps.shape;
            sh.shapeType = ParticleSystemShapeType.Cone;
            sh.radius = shapeRadius;
            sh.angle = shapeAngle;
            var col = ps.colorOverLifetime;
            col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
                      new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(0.8f, 0.5f), new GradientAlphaKey(0f, 1f) });
            col.color = g;
            var sz = ps.sizeOverLifetime;
            sz.enabled = true;
            sz.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 0.6f, 1, 1.4f));
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = Art.Particle(additive);
            r.renderMode = ParticleSystemRenderMode.Billboard;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            return ps;
        }

        // ------------------------------------------------------------ one-shot effects
        static Transform poolRoot;
        static ParticleSystem explosion, debris, sparkle, splash, dust, smokePuff, confetti;

        public static void InitPool(Transform root)
        {
            poolRoot = root;
            explosion = Create("FX_Explosion", root, true, 0.6f, 9f, 2.2f, new Color(1f, 0.6f, 0.15f), 0, -0.2f, true, 0.4f, 90f, 300);
            debris = Create("FX_Debris", root, false, 0.9f, 8f, 0.45f, new Color(0.75f, 0.5f, 0.25f), 0, 2.2f, true, 0.4f, 60f, 300);
            sparkle = Create("FX_Sparkle", root, true, 0.5f, 4f, 0.5f, new Color(1f, 0.9f, 0.4f), 0, 0f, true, 0.2f, 90f, 200);
            splash = Create("FX_Splash", root, false, 0.9f, 9f, 0.9f, new Color(0.85f, 0.97f, 1f), 0, 2.5f, true, 0.8f, 30f, 300);
            dust = Create("FX_Dust", root, false, 0.7f, 3f, 1.4f, new Color(0.9f, 0.85f, 0.75f, 0.8f), 0, -0.05f, true, 0.8f, 70f, 300);
            smokePuff = Create("FX_Smoke", root, false, 1.0f, 2f, 1.6f, new Color(0.2f, 0.2f, 0.22f, 0.9f), 0, -0.1f, true, 0.3f, 40f, 200);
            confetti = Create("FX_Confetti", root, false, 2.2f, 10f, 0.35f, Color.white, 0, 1.2f, true, 1.5f, 35f, 400);
            var cm = confetti.main;
            cm.startColor = new ParticleSystem.MinMaxGradient(new Color(1f, 0.3f, 0.3f), new Color(0.3f, 0.6f, 1f));
            var em = explosion.emission; em.rateOverTime = 0;
        }

        static void Burst(ParticleSystem ps, Vector3 pos, int count, Vector3? dir = null)
        {
            if (ps == null) return;
            ps.transform.position = pos;
            ps.transform.rotation = Quaternion.LookRotation(dir ?? Vector3.up);
            if (!ps.isPlaying) ps.Play();
            ps.Emit(count);
        }

        public static void Explosion(Vector3 p) { Burst(explosion, p, 40); Burst(smokePuff, p, 14); Burst(debris, p, 12); }
        public static void CrateBreak(Vector3 p) { Burst(debris, p, 18); Burst(sparkle, p, 10); }
        public static void Sparkle(Vector3 p) { Burst(sparkle, p, 12); }
        public static void Splash(Vector3 p) { Burst(splash, p, 50); }
        public static void Dust(Vector3 p, int n = 10) { Burst(dust, p, n); }
        public static void Smoke(Vector3 p, int n = 8) { Burst(smokePuff, p, n); }
        public static void Confetti(Vector3 p) { Burst(confetti, p, 160); }
    }
}
