using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    public enum ItemType { None, Turbo, Bomb, Missile, BoomCrate, Shield, Star }

    public static class ItemInfo
    {
        public static string Name(ItemType t)
        {
            switch (t)
            {
                case ItemType.Turbo: return "TURBO";
                case ItemType.Bomb: return "ROLL BOMB";
                case ItemType.Missile: return "HOMING ROCKET";
                case ItemType.BoomCrate: return "BOOM CRATE";
                case ItemType.Shield: return "BUBBLE SHIELD";
                case ItemType.Star: return "STAR POWER";
                default: return "";
            }
        }

        /// <summary>Position-weighted item roll (leaders get defence, the pack gets offence, the back gets catch-up).</summary>
        public static ItemType Roll(int place, int racers)
        {
            float t = racers <= 1 ? 0f : (place - 1) / (float)(racers - 1);
            ItemType[] items = { ItemType.Turbo, ItemType.Bomb, ItemType.Missile, ItemType.BoomCrate, ItemType.Shield, ItemType.Star };
            float[] lead = { 15, 25, 0, 35, 25, 0 };
            float[] mid = { 20, 25, 25, 15, 15, 0 };
            float[] back = { 25, 15, 30, 0, 10, 20 };
            float[] w = new float[items.Length];
            float sum = 0;
            for (int i = 0; i < w.Length; i++)
            {
                w[i] = t < 0.5f ? Mathf.Lerp(lead[i], mid[i], t * 2f) : Mathf.Lerp(mid[i], back[i], (t - 0.5f) * 2f);
                sum += w[i];
            }
            float r = Random.value * sum;
            for (int i = 0; i < w.Length; i++) { r -= w[i]; if (r <= 0) return items[i]; }
            return ItemType.Turbo;
        }
    }

    /// <summary>Per-kart item slot with the HUD roulette, juiced (10 fruit) upgrades and simple AI usage.</summary>
    [DefaultExecutionOrder(-10)]
    public class KartItems : MonoBehaviour
    {
        public KartController Kart;
        public ItemManager Manager;
        public ItemType Held;
        public bool Rolling;
        public float RollTimer;
        public ItemType RollShow;
        float rollTick;
        float aiTimer;
        public event System.Action<ItemType> OnItemReady;
        public event System.Action OnRollTick;

        public bool Juiced { get { return Kart.Fruit >= 10; } }

        public bool TryGive()
        {
            if (Held != ItemType.None || Rolling) return false;
            Rolling = true;
            RollTimer = Kart.IsPlayer ? 1.4f : 1.0f;
            aiTimer = Random.Range(0.6f, 2.5f);
            return true;
        }

        void Update()
        {
            float dt = Time.deltaTime;
            if (Rolling)
            {
                RollTimer -= dt;
                rollTick -= dt;
                if (rollTick <= 0f)
                {
                    rollTick = 0.07f;
                    RollShow = (ItemType)Random.Range(1, 7);
                    if (OnRollTick != null) OnRollTick();
                }
                if (RollTimer <= 0f)
                {
                    Rolling = false;
                    Held = ItemInfo.Roll(Kart.Place, Manager.Race.Karts.Count);
                    RollShow = Held;
                    if (OnItemReady != null) OnItemReady(Held);
                }
            }
            if (Held == ItemType.None || Rolling || !Kart.ControlsEnabled || Kart.Stunned || Kart.Respawning) return;
            bool use = Kart.IsPlayer ? Kart.Input.ItemPressed : AIWantsToUse(dt);
            if (use) Use();
        }

        bool AIWantsToUse(float dt)
        {
            aiTimer -= dt;
            if (aiTimer > 0f) return false;
            var race = Manager.Race;
            var s = Kart.Road.S;
            switch (Held)
            {
                case ItemType.Shield:
                case ItemType.Star:
                    return true;
                case ItemType.Turbo:
                    return Kart.Grounded && Mathf.Abs(s.CurvatureAhead(Kart.TrackIndex, 0, 30)) < 0.012f;
                case ItemType.Missile:
                    return Kart.Place > 1;
                case ItemType.Bomb:
                    foreach (var o in race.Karts)
                    {
                        if (o == Kart) continue;
                        float d = o.Progress - Kart.Progress;
                        if (d > 4f && d < 45f && o.Road == Kart.Road && Mathf.Abs(s.Lateral(o.transform.position, o.TrackIndex) - s.Lateral(Kart.transform.position, Kart.TrackIndex)) < 4f) return true;
                    }
                    return aiTimer < -6f;
                case ItemType.BoomCrate:
                    foreach (var o in race.Karts)
                    {
                        if (o == Kart) continue;
                        float d = Kart.Progress - o.Progress;
                        if (d > 3f && d < 25f) return true;
                    }
                    return aiTimer < -5f;
            }
            return false;
        }

        public void Use()
        {
            var t = Held;
            Held = ItemType.None;
            RollShow = ItemType.None;
            bool j = Juiced;
            switch (t)
            {
                case ItemType.Turbo: Kart.Boost(j ? 9f : 7.5f, j ? 2.4f : 1.6f); break;
                case ItemType.Shield: Kart.ShieldTimer = j ? 16f : 10f; break;
                case ItemType.Star: Kart.StarTimer = j ? 9f : 6.5f; Kart.Boost(4f, 1.2f); break;
                case ItemType.Bomb: Manager.SpawnBomb(Kart, j); break;
                case ItemType.Missile: Manager.SpawnMissile(Kart, j); break;
                case ItemType.BoomCrate: Manager.SpawnTrap(Kart, j); break;
            }
            Manager.Race.OnItemUsed(Kart, t);
        }
    }

    /// <summary>Owns crates, fruit, projectiles and traps for the current race.</summary>
    public class ItemManager : MonoBehaviour
    {
        public RaceManager Race;
        class Pickup { public Transform T; public Vector3 Home; public float Respawn; public bool Fruit; public float Phase; }
        readonly List<Pickup> pickups = new List<Pickup>();
        readonly List<Projectile> projectiles = new List<Projectile>();
        Mesh crateMesh, fruitMesh;
        Material crateMat, fruitMat, trapMat, bombMat;

        public void Build(TrackInstance track)
        {
            crateMesh = PropFactory.CrateMesh(1.25f);
            fruitMesh = PropFactory.FruitMesh();
            crateMat = Art.Toon("crateQ", Art.Tex("crateQ", () => Art.CrateTexture(true, new Color(0.95f, 0.62f, 0.25f), new Color(1f, 0.95f, 0.3f))), 0.25f);
            fruitMat = Art.Toon("fruit", null, 0.2f, default(Vector2), false, 0.1f, 0.5f);
            trapMat = Art.Toon("trap", Art.Tex("crateT", () => Art.CrateTexture(false, new Color(0.9f, 0.18f, 0.12f), Color.black)), 0.1f);
            bombMat = Art.Toon("bomb", null, 0.15f);
            foreach (var p in track.CrateSpots) AddPickup(p, false);
            foreach (var p in track.FruitSpots) AddPickup(p, true);
        }

        void AddPickup(Vector3 pos, bool fruit)
        {
            var go = new GameObject(fruit ? "Fruit" : "ItemCrate");
            go.transform.SetParent(transform, false);
            go.transform.position = pos;
            go.AddComponent<MeshFilter>().sharedMesh = fruit ? fruitMesh : crateMesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = fruit ? fruitMat : crateMat;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            if (fruit) go.transform.localScale = Vector3.one * 1.3f;
            pickups.Add(new Pickup { T = go.transform, Home = pos, Fruit = fruit, Phase = Random.value * 6f });
        }

        void Update()
        {
            float dt = Time.deltaTime, t = Time.time;
            var karts = Race.Karts;
            for (int i = 0; i < pickups.Count; i++)
            {
                var p = pickups[i];
                if (p.Respawn > 0f)
                {
                    p.Respawn -= dt;
                    if (p.Respawn <= 0f) { p.T.gameObject.SetActive(true); p.T.localScale = Vector3.one * 0.1f; }
                    continue;
                }
                float target = p.Fruit ? 1.3f : 1f;
                if (p.T.localScale.x < target) p.T.localScale = Vector3.one * Mathf.MoveTowards(p.T.localScale.x, target, dt * 3f);
                p.T.position = p.Home + Vector3.up * Mathf.Sin(t * 2.5f + p.Phase) * 0.18f;
                p.T.rotation = Quaternion.Euler(p.Fruit ? 0 : 12f, t * (p.Fruit ? 160f : 90f) + p.Phase * 40f, 0);
                for (int k = 0; k < karts.Count; k++)
                {
                    var kart = karts[k];
                    if (kart.Respawning) continue;
                    Vector3 kp = kart.transform.position + kart.Up * 0.7f;
                    float r = p.Fruit ? 1.7f : 2.0f;
                    if ((kp - p.T.position).sqrMagnitude > r * r) continue;
                    p.T.gameObject.SetActive(false);
                    if (p.Fruit)
                    {
                        p.Respawn = 7f;
                        kart.AddFruit(1);
                        Race.OnFruit(kart, p.T.position);
                    }
                    else
                    {
                        p.Respawn = 2.5f;
                        var items = kart.GetComponent<KartItems>();
                        bool got = items != null && items.TryGive();
                        Race.OnCrate(kart, p.T.position, got);
                    }
                    break;
                }
            }
            for (int i = projectiles.Count - 1; i >= 0; i--)
            {
                var pr = projectiles[i];
                if (pr == null || !pr.Tick(dt)) { if (pr != null) Destroy(pr.gameObject); projectiles.RemoveAt(i); }
            }
        }

        public void Clear()
        {
            foreach (var p in projectiles) if (p != null) Destroy(p.gameObject);
            projectiles.Clear();
        }

        Projectile Make(string name, Mesh mesh, Material mat, KartController owner)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = mat;
            var p = go.AddComponent<Projectile>();
            p.Manager = this; p.Owner = owner;
            projectiles.Add(p);
            return p;
        }

        static Mesh bombMesh, missileMesh;

        public void SpawnBomb(KartController owner, bool juiced)
        {
            if (bombMesh == null)
            {
                var mb = new MeshBuilder();
                mb.AddSphere(Matrix4x4.identity, 0.55f, 6, 10, new Color(0.12f, 0.12f, 0.16f), new Color(0.05f, 0.05f, 0.08f));
                mb.AddCylinder(Matrix4x4.TRS(new Vector3(0, 0.45f, 0), Quaternion.identity, Vector3.one), 0.15f, 0.15f, 0.2f, 6, new Color(0.6f, 0.6f, 0.65f));
                mb.AddSphere(Matrix4x4.TRS(new Vector3(0, 0.75f, 0), Quaternion.identity, Vector3.one), 0.12f, 3, 5, new Color(1f, 0.8f, 0.2f));
                bombMesh = mb.ToMesh("Bomb");
            }
            var p = Make("Bomb", bombMesh, bombMat, owner);
            p.Kind = ItemType.Bomb; p.Juiced = juiced;
            p.Init(owner.transform.position + owner.Fwd * 2.4f + owner.Up * 0.6f, owner.Fwd, Mathf.Max(owner.ForwardSpeed + 14f, 36f), 3.2f);
        }

        public void SpawnMissile(KartController owner, bool juiced)
        {
            if (missileMesh == null)
            {
                var mb = new MeshBuilder();
                Matrix4x4 r = Matrix4x4.TRS(new Vector3(0, 0, -0.8f), Quaternion.Euler(90, 0, 0), Vector3.one);
                mb.AddCylinder(r, 0.22f, 0.22f, 1.3f, 8, new Color(0.9f, 0.15f, 0.15f));
                mb.AddCone(Matrix4x4.TRS(new Vector3(0, 0, 0.5f), Quaternion.Euler(90, 0, 0), Vector3.one), 0.22f, 0.5f, 8, new Color(0.95f, 0.95f, 0.95f), Color.white);
                for (int i = 0; i < 4; i++)
                    mb.AddBox(Matrix4x4.TRS(new Vector3(0, 0, -0.65f), Quaternion.Euler(0, 0, i * 90), Vector3.one), new Vector3(0.05f, 0.75f, 0.35f), new Color(1f, 0.85f, 0.2f));
                missileMesh = mb.ToMesh("Missile");
            }
            var p = Make("Missile", missileMesh, bombMat, owner);
            p.Kind = ItemType.Missile; p.Juiced = juiced;
            KartController target = null;
            foreach (var k in Race.Karts) if (k.Place == owner.Place - 1) target = k;
            p.Target = target;
            p.Init(owner.transform.position + owner.Fwd * 2.4f + owner.Up * 0.9f, owner.Fwd, juiced ? 50f : 44f, 6f);
        }

        public void SpawnTrap(KartController owner, bool juiced)
        {
            var p = Make("BoomCrate", crateMesh, trapMat, owner);
            p.Kind = ItemType.BoomCrate; p.Juiced = juiced;
            p.Init(owner.transform.position - owner.Fwd * 2.6f + owner.Up * 0.65f, owner.Fwd, 0f, 90f);
        }

        /// <summary>Applies explosion damage to karts in radius.</summary>
        public void Explode(Vector3 pos, float radius, KartController owner, ItemType kind)
        {
            Particles.Explosion(pos);
            Race.OnExplosion(pos);
            foreach (var k in Race.Karts)
            {
                if (k.Respawning) continue;
                if ((k.transform.position - pos).sqrMagnitude < radius * radius)
                {
                    if (k.Hit(true)) Race.OnKartHit(k, owner, kind);
                }
            }
        }
    }

    /// <summary>Track-hugging projectile / trap. Uses the spline for walls, raycasts for ground height.</summary>
    public class Projectile : MonoBehaviour
    {
        public ItemManager Manager;
        public KartController Owner;
        public KartController Target;
        public ItemType Kind;
        public bool Juiced;
        Vector3 dir;
        float speed, life, age;
        int trackIndex;
        Road road;
        float vy;

        public void Init(Vector3 pos, Vector3 forward, float spd, float lifetime)
        {
            transform.position = pos;
            dir = Mathx.Flat(forward).normalized;
            speed = spd; life = lifetime;
            trackIndex = Owner.TrackIndex;
            road = Owner.Road;
            transform.rotation = Quaternion.LookRotation(dir);
        }

        /// <summary>Returns false when the projectile should be removed.</summary>
        public bool Tick(float dt)
        {
            age += dt;
            if (age > life) { if (Kind != ItemType.BoomCrate) Manager.Explode(transform.position, 2.5f, Owner, Kind); return false; }
            var track = Owner.Track; var s = road.S;
            Vector3 pos = transform.position;

            if (Kind == ItemType.BoomCrate)
            {
                transform.rotation = Quaternion.Euler(0, age * 40f, 0);
                // settle on the ground
                RaycastHit gh;
                if (Physics.Raycast(pos + Vector3.up * 2f, Vector3.down, out gh, 6f, Layers.GroundMask))
                    transform.position = Vector3.Lerp(pos, gh.point + Vector3.up * 0.65f, dt * 8f);
                foreach (var k in Manager.Race.Karts)
                {
                    if (k == Owner && age < 1.0f) continue;
                    if ((k.transform.position + k.Up * 0.6f - pos).sqrMagnitude < 1.9f * 1.9f && !k.Respawning)
                    {
                        Manager.Explode(pos, Juiced ? 4.5f : 2.6f, Owner, Kind);
                        return false;
                    }
                }
                return true;
            }

            // steering
            trackIndex = s.Nearest(pos, trackIndex, 10);
            // follow branches back onto the main loop / across junctions
            if (!s.Closed && trackIndex >= s.Count - 3)
            {
                Road other; int oi;
                if (track.FindRoadContaining(pos, road, out other, out oi)) { road = other; s = road.S; trackIndex = oi; }
            }
            Vector3 trackDir = Mathx.Flat(s.Fwd[s.Wrap(trackIndex + 4)]).normalized;
            Vector3 desired = trackDir;
            if (Kind == ItemType.Missile && Target != null && !Target.Respawning)
            {
                Vector3 to = Target.transform.position + Vector3.up * 0.5f - pos;
                if (to.magnitude < 60f && Vector3.Dot(Mathx.Flat(to).normalized, trackDir) > -0.2f) desired = Mathx.Flat(to).normalized;
                else
                {
                    // follow the road toward the target, stay near the centre line
                    float lat = s.Lateral(pos, trackIndex);
                    desired = (trackDir - s.Right[trackIndex] * Mathf.Clamp(lat * 0.08f, -0.5f, 0.5f)).normalized;
                }
                float turn = (Juiced ? 220f : 160f) * dt;
                dir = Vector3.RotateTowards(dir, desired, turn * Mathf.Deg2Rad, 0f);
            }
            else
            {
                // rolling bomb: keeps its line but bends with the road
                dir = Vector3.RotateTowards(dir, desired, 70f * Mathf.Deg2Rad * dt, 0f);
            }
            pos += dir * speed * dt;

            // ground following
            RaycastHit hit;
            float hover = Kind == ItemType.Missile ? 0.9f : 0.55f;
            if (Physics.Raycast(pos + Vector3.up * 2.5f, Vector3.down, out hit, 6f, Layers.GroundMask))
            {
                float gy = hit.point.y + hover;
                if (pos.y < gy + 0.3f) { pos.y = Mathf.Lerp(pos.y, gy, dt * 20f); vy = 0f; }
                else { vy -= KartController.Gravity * dt; pos.y = Mathf.Max(gy, pos.y + vy * dt); }
            }
            else
            {
                if (Kind == ItemType.Bomb) { vy -= KartController.Gravity * dt; pos.y += vy * dt; }
                if (pos.y < track.WaterLevel - 1f || pos.y < s.Pos[trackIndex].y - 12f) { Particles.Splash(pos); return false; }
            }

            // walls
            if (!road.Gap[trackIndex])
            {
                float lat = s.Lateral(pos, trackIndex);
                float lim = s.HalfWidth[trackIndex] - 0.6f;
                if (Mathf.Abs(lat) > lim && road.HasWall(trackIndex, lat < 0 ? -1 : 1))
                {
                    if (Kind == ItemType.Bomb && age > 0.15f) { transform.position = pos; Manager.Explode(pos, Juiced ? 5f : 3.2f, Owner, Kind); return false; }
                    pos -= s.Right[trackIndex] * (lat - Mathf.Sign(lat) * lim);
                    dir = Vector3.Reflect(dir, -s.Right[trackIndex] * Mathf.Sign(lat));
                    dir = Vector3.Slerp(dir, Mathx.Flat(s.Fwd[trackIndex]).normalized, 0.6f).normalized;
                }
            }
            transform.position = pos;
            transform.rotation = Quaternion.LookRotation(dir) * (Kind == ItemType.Bomb ? Quaternion.Euler(age * 720f, 0, 0) : Quaternion.Euler(0, 0, age * 360f));

            // hit test
            foreach (var k in Manager.Race.Karts)
            {
                if (k.Respawning) continue;
                if (k == Owner && age < 0.6f) continue;
                if ((k.transform.position + k.Up * 0.6f - pos).sqrMagnitude < 2.0f * 2.0f)
                {
                    Manager.Explode(pos, Kind == ItemType.Missile ? (Juiced ? 3.2f : 2.2f) : (Juiced ? 5f : 3.2f), Owner, Kind);
                    return false;
                }
            }
            return true;
        }
    }
}
