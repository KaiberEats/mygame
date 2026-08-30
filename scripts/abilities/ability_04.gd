class_name Ability04
extends Ability

## rank4: 鎌を構える（15秒）。強化時は自動鎌になる（使用時に解決）。

func apply(ctx: AbilityContext) -> void:
	ctx.effects["scythe_until"] = ctx.now + 15.0
	ctx.effects["scythe_enhanced"] = ctx.is_enhanced
	ctx.item_system.sync_player_slot()
