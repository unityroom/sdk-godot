@tool
extends EditorPlugin

const AUTOLOAD_NAME := "UnityroomClient"
const AUTOLOAD_PATH := "res://addons/unityroom_sdk/client.gd"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
