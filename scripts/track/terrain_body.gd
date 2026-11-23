extends StaticBody3D
## Terrain collider: answers surface queries from the kart's ground probe.

var terrain: TerrainBuilder


func surface_at(p: Vector3) -> int:
	if terrain == null:
		return Surfaces.GRASS
	return terrain.surface_at_xz(p.x, p.z)
