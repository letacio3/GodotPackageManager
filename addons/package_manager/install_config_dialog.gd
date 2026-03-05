@tool
extends AcceptDialog

signal install_requested(install_subpath: String, paths: PackedStringArray, ignore_asset_root: bool)

var _package: Dictionary
var _store_root: String
var _package_id: String
var _project_root: String
var _manifest_paths: PackedStringArray = []
var _install_subpath: String = ""
var _ignore_asset_root: bool = false
var _overwrite: bool = false

@onready var _asset_label: Label = $VBox/Header/AssetLabel
@onready var _install_folder_btn: Button = $VBox/Header/InstallFolderRow/ChangeFolderBtn
@onready var _install_folder_label: Label = $VBox/Header/InstallFolderRow/FolderLabel
@onready var _ignore_root_check: CheckBox = $VBox/OptionsRow/IgnoreRootCheck
@onready var _conflict_label: Label = $VBox/ConflictLabel
@onready var _contents_tree: Tree = $VBox/HSplit/ContentsSection/ContentsTree
@onready var _preview_tree: Tree = $VBox/HSplit/PreviewSection/PreviewTree

const CELL_PATH := 0


func _ready() -> void:
	get_ok_button().text = "Install"
	get_ok_button().pressed.connect(_on_install_pressed)
	_install_folder_btn.pressed.connect(_on_change_folder_pressed)
	_ignore_root_check.toggled.connect(_on_ignore_root_toggled)
	_contents_tree.item_edited.connect(_on_contents_item_edited)


func setup(package: Dictionary, store_root: String, package_id: String, overwrite: bool) -> void:
	_package = package
	_store_root = store_root
	_package_id = package_id
	_project_root = ProjectSettings.globalize_path("res://")
	_overwrite = overwrite
	_install_subpath = ""
	_ignore_asset_root = false
	title = "Configure Asset Before Installing"
	_asset_label.text = "Asset: %s" % package.get("name", package_id)
	var manifest := PackageManagerUtil.load_manifest(store_root, package_id)
	_manifest_paths = PackedStringArray(manifest.get("paths", []))
	_ignore_root_check.button_pressed = false
	_install_folder_label.text = ("res://" + _install_subpath + "/").replace("//", "/") if not _install_subpath.is_empty() else "res://"
	_populate_contents_tree()
	_update_preview()
	_update_conflict_label()


func _populate_contents_tree() -> void:
	_contents_tree.clear()
	_contents_tree.hide_root = true
	_contents_tree.column_titles_visible = false
	_contents_tree.set_column_title(0, "Contents")
	var root := _contents_tree.create_item()
	var path_to_item: Dictionary = {}
	path_to_item[""] = root
	for path in _manifest_paths:
		var p := str(path).replace("\\", "/").strip_edges()
		if p.is_empty():
			continue
		var segments := p.split("/")
		var prefix := ""
		for i in range(segments.size()):
			var seg := segments[i]
			var key := prefix + seg if prefix.is_empty() else prefix + "/" + seg
			if not path_to_item.has(key):
				var parent_key := prefix
				var parent_item: TreeItem = path_to_item.get(parent_key, root)
				var item := _contents_tree.create_item(parent_item)
				item.set_text(0, seg)
				item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
				item.set_editable(0, true)
				item.set_checked(0, true)
				if i == segments.size() - 1:
					item.set_metadata(0, p)
				path_to_item[key] = item
			prefix = key
	_update_parent_checks(_contents_tree.get_root())


func _update_parent_checks(item: TreeItem) -> void:
	if item == null:
		return
	var child := item.get_first_child()
	while child:
		_update_parent_checks(child)
		child = child.get_next()
	if item.get_child_count() > 0:
		var all_checked := true
		child = item.get_first_child()
		while child:
			if not child.is_checked(0):
				all_checked = false
				break
			child = child.get_next()
		item.set_checked(0, all_checked)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)


func _on_contents_item_edited() -> void:
	call_deferred("_apply_contents_edit")


func _apply_contents_edit() -> void:
	var item: TreeItem = _contents_tree.get_edited()
	if item == null:
		return
	var checked := item.is_checked(0)
	var child := item.get_first_child()
	while child:
		child.set_checked(0, checked)
		_set_children_checked(child, checked)
		child = child.get_next()
	_update_preview()
	_update_conflict_label()


func _set_children_checked(item: TreeItem, checked: bool) -> void:
	var child := item.get_first_child()
	while child:
		child.set_checked(0, checked)
		_set_children_checked(child, checked)
		child = child.get_next()


func _get_selected_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	_collect_checked_paths(_contents_tree.get_root(), out)
	return out


func _collect_checked_paths(item: TreeItem, out: PackedStringArray) -> void:
	if item == null:
		return
	if item.is_checked(0):
		var path: Variant = item.get_metadata(0)
		if path != null and str(path).length() > 0:
			out.append(str(path))
	var child := item.get_first_child()
	while child:
		_collect_checked_paths(child, out)
		child = child.get_next()


func _update_preview() -> void:
	_preview_tree.clear()
	_preview_tree.hide_root = true
	var root := _preview_tree.create_item()
	var base := "res://" + _install_subpath.trim_suffix("/").replace("\\", "/")
	if _install_subpath.is_empty():
		_install_folder_label.text = "res://"
		base = "res://"
	else:
		base = base.trim_suffix("/")
		_install_folder_label.text = base + "/"
	var selected := _get_selected_paths()
	var path_to_item: Dictionary = {}
	path_to_item[""] = root
	for path in selected:
		var p := path.replace("\\", "/").strip_edges()
		var install_path := p
		if _ignore_asset_root:
			var idx := p.find("/")
			install_path = p.substr(idx + 1) if idx >= 0 else p.get_file()
		var full := (base + "/" + install_path).replace("//", "/")
		var segments := install_path.split("/")
		var prefix := ""
		for i in range(segments.size()):
			var seg := segments[i]
			var key := prefix + seg if prefix.is_empty() else prefix + "/" + seg
			if not path_to_item.has(key):
				var parent_item: TreeItem = path_to_item.get(prefix, root)
				var item := _preview_tree.create_item(parent_item)
				item.set_text(0, seg)
				path_to_item[key] = item
			prefix = key


func _on_ignore_root_toggled(_on: bool) -> void:
	_ignore_asset_root = _ignore_root_check.button_pressed
	_update_preview()
	_update_conflict_label()


func _update_conflict_label() -> void:
	var selected := _get_selected_paths()
	var result := PackageManagerUtil.count_conflicts(_project_root, _install_subpath, selected, _ignore_asset_root)
	var n := result.get("count", 0)
	if n > 0:
		_conflict_label.text = "%d file(s) or folder(s) conflict with your project." % n
		_conflict_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	else:
		_conflict_label.text = "No files conflict with your project."
		_conflict_label.remove_theme_color_override("font_color")


func _on_change_folder_pressed() -> void:
	var fd := EditorFileDialog.new()
	fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	fd.access = EditorFileDialog.ACCESS_RESOURCES
	fd.title = "Select install folder (under res://)"
	fd.current_dir = _project_root
	if not _install_subpath.is_empty():
		fd.current_dir = _project_root.path_join(_install_subpath)
	fd.dir_selected.connect(_on_install_dir_selected)
	add_child(fd)
	fd.popup_centered_ratio(0.5)


func _on_install_dir_selected(dir: String) -> void:
	# EditorFileDialog with ACCESS_RESOURCES returns res:// paths, not absolute
	if dir.begins_with("res://"):
		_install_subpath = dir.substr(6).replace("\\", "/").strip_edges().trim_suffix("/")
	else:
		if not dir.begins_with(_project_root):
			return
		_install_subpath = dir.substr(_project_root.length()).lstrip("/\\").replace("\\", "/")
	_install_folder_label.text = ("res://" + _install_subpath + "/").replace("//", "/") if not _install_subpath.is_empty() else "res://"
	_update_preview()
	_update_conflict_label()


func _on_install_pressed() -> void:
	var paths := _get_selected_paths()
	if paths.is_empty():
		return
	install_requested.emit(_install_subpath, paths, _ignore_asset_root)
	hide()
