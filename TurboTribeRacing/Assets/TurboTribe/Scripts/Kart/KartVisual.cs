using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Juicy presentation layer for a kart: slide yaw, lean, squash &amp; stretch, wheel spin/steer,
    /// exhaust smoke that darkens as the slide gauge fills (the CTR timing cue), sparks, flames, shadow.
    /// </summary>
    public class KartVisual : MonoBehaviour
    {
        public KartController Kart;
        public Transform Body;
        public Transform[] Wheels;
        public Transform[] WheelPivots;
        public Transform[] Exhausts;
        public Transform[] Flames;
        public GameObject Shield, Aura;
        public Transform ShadowT;
        public SkidMarks Skids;
        ParticleSystem[] tyreSmoke = new ParticleSystem[2];
        float pitchVel, rollVel, roll, heave, heaveVel;
        int skidId;

        ParticleSystem[] smoke = new ParticleSystem[2];
        ParticleSystem[] sparks = new ParticleSystem[2];
        ParticleSystem dustTrail, boostTrail;
        float wheelAngle;
        float squash, squashVel;
        float lean, pitch;
        float lastSpeed;
        float spin;
        bool hookedEvents;

        void Start()
        {
            for (int i = 0; i < 2; i++)
            {
                smoke[i] = Particles.Create("Smoke" + i, Exhausts[i], false, 0.55f, 1.2f, 0.45f, new Color(1, 1, 1, 0.6f), 22, -0.08f, true, 0.05f, 12f, 60);
                smoke[i].transform.localRotation = Quaternion.Euler(180, 0, 0);
                smoke[i].Play();
                sparks[i] = Particles.Create("Sparks" + i, transform, true, 0.3f, 5f, 0.22f, new Color(1f, 0.8f, 0.2f), 0, 1.5f, true, 0.1f, 35f, 120);
                sparks[i].transform.localPosition = new Vector3(i == 0 ? -0.8f : 0.8f, 0.1f, -0.75f);
                sparks[i].transform.localRotation = Quaternion.Euler(-30, i == 0 ? -150 : 150, 0);
                sparks[i].Play();
            }
            dustTrail = Particles.Create("Dust", transform, false, 0.7f, 1.5f, 1.1f, new Color(0.92f, 0.85f, 0.7f, 0.7f), 0, -0.05f, true, 0.6f, 50f, 120);
            dustTrail.transform.localPosition = new Vector3(0, 0.2f, -0.9f);
            dustTrail.transform.localRotation = Quaternion.Euler(-160, 0, 0);
            dustTrail.Play();
            boostTrail = Particles.Create("BoostTrail", transform, true, 0.35f, 2f, 0.5f, new Color(1f, 0.55f, 0.15f), 0, 0f, true, 0.2f, 10f, 120);
            boostTrail.transform.localPosition = new Vector3(0, 0.72f, -1.3f);
            boostTrail.transform.localRotation = Quaternion.Euler(180, 0, 0);
            boostTrail.Play();
            for (int i = 0; i < 2; i++)
            {
                tyreSmoke[i] = Particles.Create("TyreSmoke" + i, transform, false, 0.9f, 1.4f, 1.0f, new Color(0.92f, 0.92f, 0.92f, 0.5f), 0, -0.12f, true, 0.25f, 40f, 90);
                tyreSmoke[i].transform.localPosition = new Vector3(i == 0 ? -0.8f : 0.8f, 0.25f, -0.7f);
                tyreSmoke[i].transform.localRotation = Quaternion.Euler(-150, i == 0 ? -20 : 20, 0);
                tyreSmoke[i].Play();
            }
            skidId = GetInstanceID() & 0x3FFFFF;
            if (Kart != null && !hookedEvents)
            {
                hookedEvents = true;
                Kart.OnHop += () => { squashVel += 5f; };
                Kart.OnLand += air => { squashVel -= Mathf.Clamp(air * 9f, 1f, 9f); heaveVel -= Mathf.Clamp(Kart.LandImpact * 0.12f, 0.2f, 2.2f); if (air > 0.5f) Particles.Dust(Kart.transform.position, 12); };
                Kart.OnBonk += k => { squashVel -= 4f * k; Particles.Smoke(Kart.transform.position + Kart.transform.forward * 1.2f + Vector3.up * 0.6f, 6); };
                Kart.OnSlideFail += () => { for (int i = 0; i < 2; i++) Particles.Smoke(Exhausts[i].position, 6); };
                Kart.OnFall += () => { Particles.Splash(Kart.transform.position); };
            }
        }

        void LateUpdate()
        {
            if (Kart == null) return;
            float dt = Time.deltaTime;
            var k = Kart;
            bool visible = !k.Respawning;
            Body.gameObject.SetActive(visible && !(k.InvulnTimer > 0 && !k.Stunned && k.StarTimer <= 0 && Mathf.Repeat(Time.time * 14f, 1f) < 0.35f));

            float spd = k.ForwardSpeed;
            // wheels
            wheelAngle += spd / 0.38f * Mathf.Rad2Deg * dt;
            float steerAngle = k.Input.Steer * 26f * (k.Sliding ? 0.4f : 1f) - (k.Sliding ? k.SlideDir * 14f : 0f);
            for (int i = 0; i < 4; i++)
            {
                Wheels[i].localRotation = Quaternion.Euler(wheelAngle, 0, 0);
                if (i < 2) WheelPivots[i].localRotation = Quaternion.Euler(0, steerAngle, 0);
                WheelPivots[i].gameObject.SetActive(visible);
            }

            // squash & stretch spring (crouches while a lip jump is loaded, like a coiled spring)
            float squashRest = k.LipLoaded ? -0.16f : 0f;
            squashVel += (-(squash - squashRest) * 160f - squashVel * 12f) * dt;
            squash += squashVel * dt;
            float sq = Mathf.Clamp(squash, -0.35f, 0.35f);
            Body.localScale = new Vector3(1f - sq * 0.5f, 1f + sq, 1f - sq * 0.3f);

            // suspension: spring-damped pitch (accel/brake), roll (cornering, outward) and heave (landings, bumps)
            lastSpeed = spd;
            float pitchT = Mathf.Clamp(-k.LongAccel * 0.2f, -5f, 6f) + (k.Grounded ? 0f : -5f);
            float rollT = Mathf.Clamp(k.LatAccel * 0.3f, -7f, 7f) + (k.Sliding ? k.SlideDir * 2.5f : 0f);
            pitchVel += ((pitchT - pitch) * 90f - pitchVel * 11f) * dt; pitch += pitchVel * dt;
            rollVel += ((rollT - roll) * 110f - rollVel * 12f) * dt; roll += rollVel * dt;
            heaveVel += (-heave * 140f - heaveVel * 10f) * dt; heave += heaveVel * dt;
            lean = roll;
            if (k.Stunned) spin += 720f * dt; else spin = Mathf.MoveTowards(Mathf.Repeat(spin, 360f), spin > 180 ? 360f : 0f, 1200f * dt);
            transform.localRotation = Quaternion.Euler(0f, k.SlideYaw, 0f) * Quaternion.Euler(k.Stunned ? spin * 0.5f : 0f, spin, 0);
            Body.localRotation = Quaternion.Euler(pitch, 0f, roll);
            float rumble = k.Grounded ? (Mathf.PerlinNoise(Time.time * 18f, 0.3f) - 0.5f) * 0.03f * Mathf.Clamp01(spd / 12f) * (k.Surface == SurfaceType.Offroad ? 3f : 1f) : 0f;
            Body.localPosition = new Vector3(0, Mathf.Clamp(heave, -0.25f, 0.2f) + rumble, 0);
            transform.localPosition = Vector3.zero;

            // tyre marks + tyre smoke: the planted kart scrubs hard in a slide
            bool scrub = visible && k.Grounded && (k.Sliding || k.SlipSpeed > 2.5f || (k.Input.Brake && spd > 8f));
            if (Skids != null)
            {
                Vector3 travel = k.Velocity.sqrMagnitude > 1f ? k.Velocity.normalized : k.Fwd;
                for (int w = 0; w < 4; w++)
                {
                    bool rear = w >= 2;
                    int id = skidId * 4 + w;
                    if (scrub && (rear || k.Sliding))
                    {
                        Vector3 wp = WheelPivots[w].position;
                        wp -= k.Up * Vector3.Dot(wp - k.transform.position, k.Up);
                        float a = k.Sliding ? (rear ? 0.75f : 0.35f) : Mathf.Clamp01(k.SlipSpeed / 8f) * 0.6f;
                        Skids.Add(id, wp, k.Up, travel, rear ? 0.36f : 0.28f, a);
                    }
                    else Skids.Break(id);
                }
            }
            bool onRoad = k.Surface == SurfaceType.Road || k.Surface == SurfaceType.Kicker || k.Surface == SurfaceType.Ice;
            for (int i = 0; i < 2; i++)
            {
                var e = tyreSmoke[i].emission;
                bool outer = (i == 0 && k.SlideDir > 0) || (i == 1 && k.SlideDir < 0);
                e.rateOverTime = scrub && onRoad ? (k.Sliding ? (outer ? 26f : 10f) : 12f) : 0f;
            }

            // exhaust smoke colour = slide timing cue: white -> grey -> black when the turbo window is open
            Color sc = new Color(1f, 1f, 1f, 0.55f);
            float rate = 10f + Mathf.Abs(spd) * 0.6f;
            if (k.Sliding && k.SlideBoosts < 3)
            {
                // exhaust cue: white -> grey while charging, BLACK only inside the turbo window, grey again after it
                float g = k.SlideGauge;
                if (k.InTurboZone) sc = new Color(0.04f, 0.04f, 0.05f, 0.95f);
                else if (g < k.ZoneMin) sc = Color.Lerp(new Color(1, 1, 1, 0.6f), new Color(0.5f, 0.5f, 0.55f, 0.8f), g / Mathf.Max(k.ZoneMin, 0.01f));
                else sc = new Color(0.62f, 0.6f, 0.6f, 0.7f);
                rate = 35f;
            }
            for (int i = 0; i < 2; i++)
            {
                var m = smoke[i].main; m.startColor = sc;
                var e = smoke[i].emission; e.rateOverTime = visible ? rate : 0f;
            }

            // slide sparks (colour by charge)
            bool sparkOn = visible && k.Sliding && k.Grounded;
            Color spc = k.InTurboZone ? new Color(1f, 0.3f, 0.15f) : k.SlideBoosts >= 1 ? new Color(1f, 0.75f, 0.15f) : new Color(1f, 1f, 0.7f);
            for (int i = 0; i < 2; i++)
            {
                bool outer = (i == 0 && k.SlideDir > 0) || (i == 1 && k.SlideDir < 0);
                var e = sparks[i].emission; e.rateOverTime = sparkOn ? (outer ? 45f : 15f) : 0f;
                var m = sparks[i].main; m.startColor = spc;
            }

            // offroad dust
            var de = dustTrail.emission;
            de.rateOverTime = visible && k.Grounded && k.Surface == SurfaceType.Offroad && Mathf.Abs(spd) > 4f ? 30f : (k.Sliding && k.Grounded ? 8f : 0f);

            // flames + boost trail
            float boost = k.Boosting ? Mathf.Clamp01(0.6f + k.BoostBonus / 12f) : 0f;
            for (int i = 0; i < 2; i++)
            {
                float flick = boost > 0 ? (0.85f + Mathf.PerlinNoise(Time.time * 25f, i * 3f) * 0.45f) : 0f;
                Flames[i].localScale = Vector3.Lerp(Flames[i].localScale, Vector3.one * boost * flick * (visible ? 1.5f : 0f), Mathx.Damp(20f, dt));
            }
            var be = boostTrail.emission; be.rateOverTime = visible && boost > 0 ? 60f : 0f;

            Shield.SetActive(visible && k.ShieldTimer > 0f);
            if (Shield.activeSelf) Shield.transform.localScale = Vector3.one * (1f + Mathf.Sin(Time.time * 6f) * 0.04f);
            Aura.SetActive(visible && k.StarTimer > 0f);
            if (Aura.activeSelf) Aura.transform.localRotation = Quaternion.Euler(0, Time.time * 200f, 0);

            // blob shadow on the ground
            RaycastHit hit;
            if (visible && Physics.Raycast(k.transform.position + Vector3.up * 1.5f, Vector3.down, out hit, 25f, Layers.GroundMask))
            {
                ShadowT.gameObject.SetActive(true);
                float h = k.transform.position.y - hit.point.y;
                ShadowT.position = hit.point + hit.normal * 0.06f;
                ShadowT.rotation = Quaternion.LookRotation(Vector3.ProjectOnPlane(k.Fwd, hit.normal), hit.normal) * Quaternion.Euler(0, k.SlideYaw, 0);
                float sc2 = Mathf.Clamp(1f - h * 0.08f, 0.4f, 1f);
                ShadowT.localScale = new Vector3(sc2, 1, sc2);
            }
            else ShadowT.gameObject.SetActive(false);
        }
    }
}
