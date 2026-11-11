using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// CTR-style chase camera: low and close, follows the travel direction (not the slide yaw),
    /// widens FOV with speed/boost, small shake on impacts, pulls in to avoid clipping terrain.
    /// </summary>
    public class CameraRig : MonoBehaviour
    {
        public KartController Target;
        public Camera Cam;
        public float Distance = 6.2f;
        public float Height = 2.5f;
        public float LookAhead = 3.5f;
        public bool Orbit;          // used for intro / results fly-around
        float orbitAngle;
        Vector3 smoothFwd = Vector3.forward;
        Vector3 vel;
        float shake;
        float fov = 62f;

        public static CameraRig Create(Transform parent)
        {
            var go = new GameObject("CameraRig");
            go.transform.SetParent(parent, false);
            var rig = go.AddComponent<CameraRig>();
            var cam = go.AddComponent<Camera>();
            cam.nearClipPlane = 0.2f;
            cam.farClipPlane = 1500f;
            cam.fieldOfView = 62f;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.6f, 0.8f, 1f);
            go.tag = "MainCamera";
            go.AddComponent<AudioListener>();
            rig.Cam = cam;
            return rig;
        }

        public void Shake(float amount) { shake = Mathf.Max(shake, amount); }

        public void SnapBehind()
        {
            if (Target == null) return;
            smoothFwd = Target.Fwd;
            transform.position = Target.transform.position - Target.Fwd * Distance + Vector3.up * Height;
            transform.LookAt(Target.transform.position + Vector3.up * 1.2f + Target.Fwd * LookAhead);
            vel = Vector3.zero;
        }

        void LateUpdate()
        {
            if (Target == null) return;
            float dt = Mathf.Max(Time.deltaTime, 1e-4f);
            Vector3 kp = Target.transform.position;
            if (Orbit)
            {
                orbitAngle += dt * 25f;
                Vector3 off = Quaternion.Euler(0, orbitAngle, 0) * new Vector3(0, 3.2f, -8.5f);
                transform.position = Vector3.Lerp(transform.position, kp + off, Mathx.Damp(3f, dt));
                transform.rotation = Quaternion.LookRotation(kp + Vector3.up * 1f - transform.position);
                Cam.fieldOfView = Mathf.Lerp(Cam.fieldOfView, 55f, Mathx.Damp(3f, dt));
                return;
            }
            // travel direction: velocity when moving, otherwise heading
            Vector3 travel = Mathx.Flat(Target.Velocity);
            Vector3 head = Mathx.Flat(Target.Fwd).normalized;
            Vector3 dir = travel.magnitude > 4f ? Vector3.Slerp(head, travel.normalized, 0.5f) : head;
            if (Target.Sliding) dir = Quaternion.Euler(0, Target.SlideDir * 6f, 0) * dir; // swing slightly into the slide
            if (Target.Stunned || Target.Respawning) dir = smoothFwd;
            smoothFwd = Vector3.Slerp(smoothFwd, dir.normalized, Mathx.Damp(Target.Sliding ? 4.5f : 6f, dt));
            if (smoothFwd.sqrMagnitude < 0.01f) smoothFwd = head;

            float spdF = Mathf.Clamp01(Target.ForwardSpeed / 30f);
            float dist = Distance + spdF * 0.9f + (Target.Boosting ? 0.6f : 0f);
            float height = Height + (Target.Grounded ? 0f : 0.4f);
            Vector3 desired = kp - smoothFwd * dist + Vector3.up * height;

            // keep camera above the ground / out of hills
            RaycastHit hit;
            Vector3 from = kp + Vector3.up * 1.5f;
            Vector3 toCam = desired - from;
            if (Physics.SphereCast(from, 0.3f, toCam.normalized, out hit, toCam.magnitude, Layers.GroundMask))
                desired = from + toCam.normalized * Mathf.Max(1.5f, hit.distance - 0.2f);
            if (Physics.Raycast(desired + Vector3.up * 3f, Vector3.down, out hit, 4.2f, Layers.GroundMask) && hit.point.y + 0.8f > desired.y)
                desired.y = hit.point.y + 0.8f;

            transform.position = Vector3.SmoothDamp(transform.position, desired, ref vel, 0.06f, 200f, dt);
            Vector3 look = kp + Vector3.up * 1.15f + smoothFwd * LookAhead;
            Quaternion rot = Quaternion.LookRotation(look - transform.position, Vector3.up);
            if (shake > 0f)
            {
                shake = Mathf.MoveTowards(shake, 0f, dt * 2.5f);
                rot *= Quaternion.Euler((Mathf.PerlinNoise(Time.time * 40f, 0) - 0.5f) * shake * 6f, (Mathf.PerlinNoise(0, Time.time * 40f) - 0.5f) * shake * 6f, 0);
            }
            transform.rotation = rot;
            float targetFov = 62f + spdF * 8f + (Target.Boosting ? 8f : 0f);
            fov = Mathf.Lerp(fov, targetFov, Mathx.Damp(4f, dt));
            Cam.fieldOfView = fov;
        }
    }
}
