class_name AbilityContext
extends RefCounted

## 能力発動時に各 Ability へ渡す文脈。match(_game)・発動者・強化フラグ・時刻・状態辞書。

var game: Node
var caster: Node3D
var is_enhanced: bool = false
var now: float = 0.0
var effects: Dictionary
