class_name VisionComponent
extends Node

## この参加者が「見ている」情報の時限状態。
## card_view : 覗き見中の相手手札（空 = なし）。target/targets と until を持つ。
## map_reveal: マップ開示（空 = なし）。positions と until を持つ。

var card_view: Dictionary = {}
var map_reveal: Dictionary = {}
