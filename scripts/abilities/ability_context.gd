class_name AbilityContext
extends RefCounted

## 能力発動時に各 Ability へ渡す文脈。発動者・強化フラグ・時刻・状態辞書と、能力が触る System 群。

var caster: Node3D
var is_enhanced: bool = false
var now: float = 0.0
var effects: Dictionary
var combat: CombatSystem
var item_system: ItemSystem
var status_system: StatusSystem
var participants: Participants
var deck: Node
