class_name Ability09
extends Ability

## rank9: レイピア（カウンター）。強化時は持続6秒/通常3秒。

func apply(ctx: AbilityContext) -> void:
	ctx.effects["counter_duration"] = 6.0 if ctx.is_enhanced else 3.0
	ctx.effects["counter_until"] = ctx.now + float(ctx.effects["counter_duration"])
	ctx.item_system.sync_player_slot()
