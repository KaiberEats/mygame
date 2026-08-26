class_name Ability12
extends Ability

## rank12: 盾（バリア。kill を吸収）。強化時2回/通常1回。

func apply(ctx: AbilityContext) -> void:
	ctx.effects["barrier_charges"] = 2 if ctx.is_enhanced else 1
	ctx.game._combat.set_barrier_visual(ctx.caster, true)
	ctx.game._item_system.sync_player_slot()
