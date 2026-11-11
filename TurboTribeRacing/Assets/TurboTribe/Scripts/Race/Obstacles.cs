using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Track hazards designed to break the "one perfect line": each one occupies the ideal line for part of
    /// its cycle, so drivers must read the timing, pick a side, or risk it.
    ///  pillar   - solid stone totem in the road (choose a side; bounces you hard)
    ///  crab     - scuttles across a lane back and forth (small spin-out)
    ///  boulder  - rolls across the full width every 'period' seconds (big hit)
    ///  pendulum - heavy log swinging across the road from an overhead gantry (big hit)
    ///  geyser   - bubbles as a warning, then erupts and launches karts (spin-out)
    ///  penguin  - waddles across slowly in a group (small spin-out)
    ///  pusher   - stone block slides in from the side, periodically narrowing the road (solid)
    /// </summary>
    public class Obstacle
    {
        public string Type;
        public Road Road;
        public int Index;
        public float Lane;       // lateral metres
        public float Size = 1f;
        public float Period = 4f, Phase;
        public Vector3 Pos;       // current hazard centre
        public float Radius = 1f;
        public bool Solid;        // pushes karts out instead of hitting them
        public bool Active = true;
        public bool BigHit;
        public float Launch;      // upward velocity for geysers
        public Transform Visual;
        public Transform Part;    // animated sub-part
        public float Warn;        // 0..1 warning intensity (geyser bubbling)
        float hitCooldown;

        Vector3 Base(float lat, float lift = 0f) { return Road.S.PointAt(Index, lat, lift); }

        public void Tick(float time, float dt)
        {
            var s = Road.S;
            float hw = s.HalfWidth[Index];
            float ph = (time / Period + Phase) % 1f;
            if (hitCooldown > 0) hitCooldown -= dt;
            switch (Type)
            {
                case "pillar":
                    Pos = Base(Lane, 1f); Radius = 1.4f * Size; Solid = true; Active = true;
                    break;
                case "crab":
                    {
                        float x = Mathf.Sin(ph * Mathf.PI * 2f) * hw * 0.38f * Size;
                        Pos = Base(Lane + x, 0.4f); Radius = 0.95f; Active = true;
                        if (Visual != null)
                        {
                            Visual.position = Base(Lane + x, 0f);
                            Visual.rotation = Quaternion.LookRotation(s.Fwd[Index], s.Up[Index]) * Quaternion.Euler(0, Mathf.Sin(time * 14f) * 6f, 0);
                        }
                        break;
                    }
                case "boulder":
                    {
                        // roll from one wall to the other during the first 45% of the cycle, then reset off-road
                        float u = ph / 0.45f;
                        Active = u <= 1f;
                        float dir = (Mathf.FloorToInt(time / Period + Phase) % 2 == 0) ? 1f : -1f;
                        float r = 1.9f * Size;
                        float x = Mathf.Lerp(-hw - 3f, hw + 3f, Mathf.Clamp01(u)) * dir;
                        Pos = Base(x, r); Radius = r + 0.3f; BigHit = true;
                        if (Visual != null)
                        {
                            Visual.gameObject.SetActive(Active);
                            Visual.position = Pos;
                            Visual.rotation = Quaternion.AngleAxis(-x / r * Mathf.Rad2Deg * dir, s.Fwd[Index]);
                        }
                        break;
                    }
                case "pendulum":
                    {
                        float ang = Mathf.Sin(ph * Mathf.PI * 2f) * 62f;
                        float L = 7.2f;
                        Vector3 pivot = Base(Lane, L + 1.2f);
                        Vector3 dirDown = Quaternion.AngleAxis(ang, s.Fwd[Index]) * -s.Up[Index];
                        Pos = pivot + dirDown * L; Radius = 1.6f; BigHit = true;
                        Active = true;
                        if (Part != null) Part.rotation = Quaternion.LookRotation(s.Fwd[Index], -dirDown);
                        break;
                    }
                case "geyser":
                    {
                        // idle -> warn (last 30% before eruption) -> erupt 18%
                        Pos = Base(Lane, 0.5f); Radius = 2.4f * Size; Launch = 13f;
                        Active = ph > 0.82f;
                        Warn = ph > 0.52f && ph <= 0.82f ? (ph - 0.52f) / 0.3f : (Active ? 1f : 0f);
                        if (Part != null)
                        {
                            float hgt = Active ? Mathf.Sin((ph - 0.82f) / 0.18f * Mathf.PI) * 9f : Warn * 0.6f;
                            Part.localScale = new Vector3(1.4f + Warn * 0.3f, Mathf.Max(0.05f, hgt), 1.4f + Warn * 0.3f) * Size;
                        }
                        break;
                    }
                case "penguin":
                    {
                        float x = Mathf.Lerp(-hw * 0.9f, hw * 0.9f, Mathf.PingPong(ph * 2f, 1f));
                        Pos = Base(x, 0.5f); Radius = 0.9f; Active = true;
                        if (Visual != null)
                        {
                            Visual.position = Base(x, 0f);
                            Vector3 walk = s.Right[Index] * (ph % 0.5f < 0.25f ? 1f : -1f);
                            Visual.rotation = Quaternion.LookRotation(walk, s.Up[Index]) * Quaternion.Euler(0, 0, Mathf.Sin(time * 9f) * 9f);
                        }
                        break;
                    }
                case "pusher":
                    {
                        // slides in for 40% of the cycle, covering ~45% of the road width
                        float u = Mathf.Clamp01(Mathf.Sin(ph * Mathf.PI * 2f) * 1.6f);
                        float side = Lane >= 0 ? 1f : -1f;
                        float x = side * (hw + 2f - u * hw * 0.9f);
                        Pos = Base(x, 1.2f); Radius = 2.3f; Solid = true; Active = true;
                        if (Visual != null) Visual.position = Base(x, 0f);
                        break;
                    }
            }
        }

        /// <summary>Kart interaction. Returns true if the kart was affected.</summary>
        public bool Interact(KartController k)
        {
            if (!Active || k.Respawning) return false;
            Vector3 kp = k.transform.position + k.Up * 0.6f;
            Vector3 d = kp - Pos;
            if (Type != "pendulum" && Type != "boulder") d.y = 0f;
            float minD = Radius + 0.8f;
            if (d.sqrMagnitude > minD * minD) return false;
            if (Solid)
            {
                Vector3 flat = Mathx.Flat(d);
                if (flat.sqrMagnitude < 1e-4f) flat = -k.Fwd;
                Vector3 nrm = flat.normalized;
                float pen = minD - flat.magnitude;
                k.transform.position += nrm * pen;
                float vn = Vector3.Dot(k.Velocity, nrm);
                if (vn < 0f)
                {
                    float spd = k.Velocity.magnitude;
                    k.Velocity -= nrm * vn * 1.5f;
                    k.Velocity *= 0.7f;
                    k.NotifyBonk(Mathf.Clamp01(-vn / Mathf.Max(spd, 1f)));
                }
                return true;
            }
            if (hitCooldown > 0f) return false;
            hitCooldown = 0.25f;
            if (Type == "geyser")
            {
                if (k.Hit(false)) { k.Velocity += Vector3.up * Launch; return true; }
                return false;
            }
            return k.Hit(BigHit);
        }
    }

    /// <summary>Spawns obstacle visuals and runs their logic + kart interaction each frame.</summary>
    public class ObstacleManager : MonoBehaviour
    {
        public readonly List<Obstacle> Items = new List<Obstacle>();
        public List<KartController> Karts;
        public System.Action<Obstacle, KartController> OnKartHit;
        float time;
        public bool BuildVisuals = true;

        public void Build(TrackInstance track, int seed)
        {
            var rng = new Rng(seed + 991);
            foreach (var od in track.Data.obstacles)
            {
                Road road = null;
                foreach (var r in track.Roads) if (r.Name == od.road) road = r;
                if (road == null) continue;
                int count = Mathf.Max(1, od.count);
                for (int c = 0; c < count; c++)
                {
                    int idx = road.S.IndexOfParam(od.t);
                    idx = road.S.Wrap(idx + Mathf.RoundToInt((c - (count - 1) * 0.5f) * od.spread / road.S.Step));
                    var o = new Obstacle
                    {
                        Type = od.type, Road = road, Index = idx, Lane = od.lane * road.S.HalfWidth[idx], Size = od.size,
                        Period = Mathf.Max(0.5f, od.period), Phase = od.phase + c * 0.37f
                    };
                    if (od.type == "penguin" || od.type == "crab") o.Phase = od.phase + c * 0.21f;
                    if (BuildVisuals) BuildVisual(o, rng);
                    o.Tick(0f, 0f);
                    Items.Add(o);
                }
            }
        }

        public void Step(float dt)
        {
            time += dt;
            foreach (var o in Items)
            {
                o.Tick(time, dt);
                if (Karts == null) continue;
                foreach (var k in Karts)
                    if (o.Interact(k) && !o.Solid && OnKartHit != null) OnKartHit(o, k);
            }
        }

        void Update() { Step(Time.deltaTime); }

        // ------------------------------------------------------------------ visuals
        static Color H(string hex) { Color c; ColorUtility.TryParseHtmlString(hex, out c); return c; }

        GameObject Obj(string name, MeshBuilder mb, Material mat)
        {
            var go = mb.ToObject(name, transform, mat);
            TrackBuilder.Shadows(go, true, false);
            return go;
        }

        void BuildVisual(Obstacle o, Rng rng)
        {
            var s = o.Road.S; int i = o.Index;
            Material mat = Art.Toon("obstacle", Art.Tex("grain", () => Art.GrainTexture(64, 0.12f, 11)), 0, default(Vector2), false, 0.1f, 0.3f, 0.35f);
            Quaternion q = Quaternion.LookRotation(s.Fwd[i], s.Up[i]);
            switch (o.Type)
            {
                case "pillar":
                    {
                        var mb = new MeshBuilder();
                        float r = 1.4f * o.Size;
                        mb.AddNaturalRock(Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(1.1f, 0.5f, 1.1f)), r * 1.25f, H("#7A6A58"), H("#5E8A3C"), rng, 1, 0.25f);
                        mb.AddLathe(Matrix4x4.identity, new[] { new Vector2(r, 0), new Vector2(r * 0.92f, 1.5f), new Vector2(r * 0.95f, 3.2f), new Vector2(r * 0.86f, 4.6f), new Vector2(r * 1.05f, 5f), new Vector2(0.01f, 5.6f) }, 12,
                            new[] { H("#8E816C"), H("#A89A82"), H("#9A8C74"), H("#A89A82"), H("#C2B49A"), H("#C2B49A") });
                        // carved face
                        Vector3 f = Vector3.forward * -r * 0.93f;
                        for (int e = -1; e <= 1; e += 2)
                            mb.AddSphere(Matrix4x4.TRS(f + new Vector3(e * r * 0.35f, 3.5f, 0), Quaternion.identity, new Vector3(1f, 0.6f, 0.4f)), r * 0.22f, 6, 8, H("#3A3028"));
                        mb.AddRoundedBox(Matrix4x4.TRS(f + new Vector3(0, 2.1f, 0), Quaternion.identity, Vector3.one), new Vector3(r * 0.9f, 0.3f, 0.3f), 0.1f, H("#3A3028"), 1);
                        var go = Obj("Pillar", mb, mat);
                        go.transform.SetPositionAndRotation(s.PointAt(i, o.Lane, -0.2f), q);
                        o.Visual = go.transform;
                        break;
                    }
                case "crab":
                    {
                        var mb = new MeshBuilder();
                        Color shell = H("#E8452A"), belly = H("#FF9A6A");
                        mb.AddSphere(Matrix4x4.TRS(new Vector3(0, 0.55f, 0), Quaternion.identity, new Vector3(1.3f, 0.6f, 1f)), 0.55f, 10, 14, shell, belly);
                        for (int sd = -1; sd <= 1; sd += 2)
                        {
                            for (int l = 0; l < 3; l++)
                            {
                                Vector3 a = new Vector3(sd * 0.55f, 0.5f, -0.25f + l * 0.25f);
                                mb.AddTube(new[] { a, a + new Vector3(sd * 0.45f, 0.25f, 0), a + new Vector3(sd * 0.75f, -0.5f, 0) }, new[] { 0.07f, 0.06f, 0.03f }, 5, shell);
                            }
                            // claws
                            Vector3 c = new Vector3(sd * 0.55f, 0.65f, 0.45f);
                            mb.AddTube(new[] { c, c + new Vector3(sd * 0.25f, 0.2f, 0.35f) }, new[] { 0.09f, 0.08f }, 5, shell);
                            mb.AddSphere(Matrix4x4.TRS(c + new Vector3(sd * 0.3f, 0.3f, 0.55f), Quaternion.identity, new Vector3(1f, 0.6f, 1.3f)), 0.22f, 6, 8, shell);
                            // eye stalks
                            mb.AddTube(new[] { new Vector3(sd * 0.18f, 0.8f, 0.35f), new Vector3(sd * 0.22f, 1.15f, 0.4f) }, new[] { 0.04f, 0.035f }, 4, shell);
                            mb.AddSphere(Matrix4x4.TRS(new Vector3(sd * 0.22f, 1.2f, 0.42f), Quaternion.identity, Vector3.one), 0.09f, 6, 8, Color.white);
                            mb.AddSphere(Matrix4x4.TRS(new Vector3(sd * 0.22f, 1.21f, 0.5f), Quaternion.identity, Vector3.one), 0.045f, 4, 6, H("#111111"));
                        }
                        var go = Obj("Crab", mb, mat);
                        go.transform.localScale = Vector3.one * 1.5f;
                        o.Visual = go.transform;
                        break;
                    }
                case "boulder":
                    {
                        var mb = new MeshBuilder();
                        mb.AddNaturalRock(Matrix4x4.identity, 1.9f * o.Size, H("#8A7460"), H("#A08A72"), rng, 2, 0.12f, true);
                        var go = Obj("Boulder", mb, mat);
                        o.Visual = go.transform;
                        // ramp-side warning signs
                        var sign = new MeshBuilder();
                        for (int sd = -1; sd <= 1; sd += 2)
                        {
                            Vector3 b = s.PointAt(i, sd * (s.HalfWidth[i] + 2.2f), 0);
                            sign.AddTube(new[] { b, b + Vector3.up * 3f }, new[] { 0.1f, 0.1f }, 5, H("#4A3A2A"));
                            sign.AddRoundedBox(Matrix4x4.TRS(b + Vector3.up * 3.1f, Quaternion.LookRotation(-s.Fwd[i]) * Quaternion.Euler(0, 0, 45), Vector3.one), new Vector3(1.1f, 1.1f, 0.08f), 0.08f, H("#FFC21A"), 1);
                        }
                        Obj("BoulderSigns", sign, mat);
                        break;
                    }
                case "pendulum":
                    {
                        var frame = new MeshBuilder();
                        float hw = s.HalfWidth[i] + TrackBuilder.WallThick + 0.6f;
                        float L = 7.2f;
                        Color wood = H("#6E4A2C");
                        for (int sd = -1; sd <= 1; sd += 2)
                        {
                            Vector3 b = s.PointAt(i, sd * hw, -0.5f);
                            frame.AddRoundedBox(Matrix4x4.TRS(b + Vector3.up * (L + 1.2f) * 0.5f, q, Vector3.one), new Vector3(0.9f, L + 2.6f, 0.9f), 0.15f, wood, 1);
                        }
                        frame.AddRoundedBox(Matrix4x4.TRS(s.PointAt(i, 0, L + 1.5f), q, Vector3.one), new Vector3(hw * 2f + 1f, 0.8f, 0.9f), 0.15f, wood, 1);
                        Obj("PendulumFrame", frame, mat);
                        var arm = new MeshBuilder();
                        // local: pivot at origin, hanging down -Y in the 'up' axis of the rotation we set (LookRotation(fwd, -down))
                        arm.AddTube(new[] { Vector3.zero, new Vector3(0, -L + 0.8f, 0) }, new[] { 0.08f, 0.08f }, 5, H("#3A3A3E"));
                        arm.AddLathe(Matrix4x4.TRS(new Vector3(0, -L, -1.6f), Quaternion.Euler(90, 0, 0), Vector3.one),
                            new[] { new Vector2(0.01f, 0), new Vector2(0.75f, 0.1f), new Vector2(0.9f, 1.6f), new Vector2(0.75f, 3.1f), new Vector2(0.01f, 3.2f) }, 10,
                            new[] { H("#C9A06A"), H("#7A5232"), H("#6A4428"), H("#7A5232"), H("#C9A06A") });
                        var pivotGo = new GameObject("PendulumPivot");
                        pivotGo.transform.SetParent(transform, false);
                        pivotGo.transform.position = s.PointAt(i, o.Lane, L + 1.2f);
                        var armGo = arm.ToObject("PendulumLog", pivotGo.transform, mat);
                        TrackBuilder.Shadows(armGo, true, false);
                        o.Part = pivotGo.transform;
                        break;
                    }
                case "geyser":
                    {
                        var ring = new MeshBuilder();
                        for (int k = 0; k < 9; k++)
                        {
                            float a = k / 9f * Mathf.PI * 2f;
                            ring.AddNaturalRock(Matrix4x4.TRS(new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * 2.3f * o.Size, Quaternion.identity, new Vector3(1.2f, 0.45f, 1f)), 0.55f, H("#6A6A70"), H("#9AA0A8"), rng, 1, 0.3f);
                        }
                        ring.AddCylinder(Matrix4x4.TRS(Vector3.up * 0.06f, Quaternion.identity, Vector3.one), 2f * o.Size, 2f * o.Size, 0.04f, 16, H("#4FC6E8"));
                        var go = Obj("Geyser", ring, mat);
                        go.transform.SetPositionAndRotation(s.PointAt(i, o.Lane, 0f), q);
                        var col = new MeshBuilder();
                        col.AddLathe(Matrix4x4.identity, new[] { new Vector2(1f, 0), new Vector2(0.75f, 0.3f), new Vector2(0.55f, 0.8f), new Vector2(0.75f, 0.95f), new Vector2(0.01f, 1f) }, 12,
                            new[] { new Color(0.75f, 0.95f, 1f, 0.7f), new Color(0.85f, 0.97f, 1f, 0.8f), new Color(1f, 1f, 1f, 0.75f), new Color(1f, 1f, 1f, 0.6f), new Color(1f, 1f, 1f, 0.5f) });
                        var cgo = col.ToObject("GeyserWater", go.transform, Art.Particle(false));
                        o.Part = cgo.transform;
                        break;
                    }
                case "penguin":
                    {
                        var mb = new MeshBuilder();
                        Color black = H("#22263A"), white = H("#F4F6FA"), orange = H("#FF9A1E");
                        mb.AddSphere(Matrix4x4.TRS(new Vector3(0, 0.75f, 0), Quaternion.identity, new Vector3(0.9f, 1.25f, 0.85f)), 0.6f, 10, 14, black, black * 0.8f);
                        mb.AddSphere(Matrix4x4.TRS(new Vector3(0, 0.7f, 0.18f), Quaternion.identity, new Vector3(0.75f, 1.1f, 0.6f)), 0.55f, 10, 14, white);
                        mb.AddSphere(Matrix4x4.TRS(new Vector3(0, 1.55f, 0.05f), Quaternion.identity, Vector3.one), 0.38f, 10, 14, black);
                        mb.AddCone(Matrix4x4.TRS(new Vector3(0, 1.5f, 0.38f), Quaternion.Euler(90, 0, 0), Vector3.one), 0.1f, 0.3f, 6, orange, orange);
                        for (int sd = -1; sd <= 1; sd += 2)
                        {
                            mb.AddSphere(Matrix4x4.TRS(new Vector3(sd * 0.14f, 1.62f, 0.32f), Quaternion.identity, Vector3.one), 0.08f, 6, 8, Color.white);
                            mb.AddSphere(Matrix4x4.TRS(new Vector3(sd * 0.14f, 1.63f, 0.38f), Quaternion.identity, Vector3.one), 0.04f, 4, 6, H("#111111"));
                            mb.AddSphere(Matrix4x4.TRS(new Vector3(sd * 0.55f, 0.9f, 0f), Quaternion.Euler(0, 0, sd * 20), new Vector3(0.25f, 1f, 0.5f)), 0.45f, 6, 8, black);
                            mb.AddSphere(Matrix4x4.TRS(new Vector3(sd * 0.2f, 0.05f, 0.2f), Quaternion.identity, new Vector3(1f, 0.35f, 1.4f)), 0.18f, 5, 8, orange);
                        }
                        var go = Obj("Penguin", mb, mat);
                        go.transform.localScale = Vector3.one * 1.25f;
                        o.Visual = go.transform;
                        break;
                    }
                case "pusher":
                    {
                        var mb = new MeshBuilder();
                        mb.AddRoundedBox(Matrix4x4.TRS(new Vector3(0, 1.3f, 0), Quaternion.identity, Vector3.one), new Vector3(4.2f, 2.6f, 3.4f), 0.3f, H("#8E816C"), 2, H("#A89A82"));
                        for (int k = 0; k < 3; k++)
                            mb.AddRoundedBox(Matrix4x4.TRS(new Vector3(0, 0.7f + k * 0.7f, -1.72f), Quaternion.identity, Vector3.one), new Vector3(4.3f, 0.18f, 0.08f), 0.04f, H("#FFC21A"), 1);
                        var go = Obj("Pusher", mb, mat);
                        go.transform.rotation = Quaternion.LookRotation(s.Fwd[i], s.Up[i]);
                        o.Visual = go.transform;
                        break;
                    }
            }
        }
    }
}
