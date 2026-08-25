class_name TargetingService
extends RefCounted

## 照準（視線・中心ドット判定）でのターゲット探索。状態を持たない純ロジック。
## クールダウンや所持判定などの「行動可否ゲート」は呼び出し側が担う。


## 視界中心に最も近い対象を返す。for_change=true のときは「自分にスタンされた相手」に限定。
func find_aimed(attacker: Node3D, participants: Array[Node3D], change_killers: Dictionary, for_change: bool, kill_distance: float, center_dot: float) -> Node3D:
	var view_origin: Vector3 = attacker.get_view_origin()
	var view_forward: Vector3 = attacker.get_view_forward()
	var best_target: Node3D = null
	var best_dot := center_dot

	for target in participants:
		if target == attacker:
			continue
		if for_change:
			if not target.is_stunned() or change_killers.get(target) != attacker or target.hand.is_empty():
				continue
		elif target.is_stunned():
			continue

		var to_target := target.global_position + Vector3(0.0, 1.0, 0.0) - view_origin
		var distance := to_target.length()
		if distance > kill_distance:
			continue

		var center := view_forward.dot(to_target.normalized())
		if center > best_dot:
			best_dot = center
			best_target = target

	return best_target


## 最も近い他参加者を返す。
func find_nearest(participant: Node3D, participants: Array[Node3D]) -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for target in participants:
		if target == participant:
			continue
		var distance := participant.global_position.distance_squared_to(target.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = target
	return nearest


## ミサイルの着弾対象。local_player が撃つときは視界中心、それ以外は最も近い視線の通る相手。
func find_visible_missile(shooter: Node3D, participants: Array[Node3D], local_player: Node3D, center_dot: float) -> Node3D:
	var candidates: Array[Node3D] = []
	if shooter == local_player:
		var best_dot := center_dot
		for target in participants:
			if target == shooter:
				continue
			var direction: Vector3 = (target.global_position + Vector3.UP - shooter.get_view_origin()).normalized()
			var dot: float = shooter.get_view_forward().dot(direction)
			if dot > best_dot and has_line_of_sight(shooter, target):
				best_dot = dot
				candidates = [target]
	else:
		for target in participants:
			if target != shooter and has_line_of_sight(shooter, target):
				candidates.append(target)
		candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return shooter.global_position.distance_squared_to(a.global_position) < shooter.global_position.distance_squared_to(b.global_position)
		)
	return candidates[0] if not candidates.is_empty() else null


## shooter から target まで遮蔽物が無いか。
func has_line_of_sight(shooter: Node3D, target: Node3D) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		shooter.get_view_origin(),
		target.global_position + Vector3.UP
	)
	query.exclude = [shooter]
	var result: Dictionary = shooter.get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.get("collider") == target
