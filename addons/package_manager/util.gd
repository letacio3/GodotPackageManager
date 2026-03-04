@tool
class_name PackageManagerUtil
extends RefCounted

const SETTINGS_PATH := "user://package_manager/settings.cfg"
const DEFAULT_STORE_PATH := "user://package_manager/packs"

## Returns the configured store path, or default.
static func get_store_path() -> String:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(ProjectSettings.globalize_path(SETTINGS_PATH)):
		var e := cfg.load(ProjectSettings.globalize_path(SETTINGS_PATH))
		if e == OK:
			return cfg.get_value("package_manager", "store_path", DEFAULT_STORE_PATH)
	return DEFAULT_STORE_PATH


## Persist store path to settings.
static func set_store_path(path: String) -> Error:
	var base := ProjectSettings.globalize_path("user://package_manager")
	if not DirAccess.dir_exists_absolute(base):
		var d := DirAccess.open(ProjectSettings.globalize_path("user://"))
		if d == null:
			return FAILED
		if d.make_dir_recursive("package_manager") != OK:
			return FAILED
	var cfg := ConfigFile.new()
	cfg.set_value("package_manager", "store_path", path)
	return cfg.save(ProjectSettings.globalize_path(SETTINGS_PATH))


## Globalize path (user:// or res://) to absolute.
static func globalize(p: String) -> String:
	if p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.begins_with("res://"):
		return ProjectSettings.globalize_path(p)
	return p


## Copy a file or directory recursively from src to dst (absolute paths).
static func copy_recursive(src: String, dst: String) -> Error:
	if not FileAccess.file_exists(src) and not DirAccess.dir_exists_absolute(src):
		return ERR_FILE_NOT_FOUND
	if DirAccess.dir_exists_absolute(src):
		return _copy_dir_recursive(src, dst)
	else:
		var dir := dst.get_base_dir()
		if _ensure_dir_absolute(dir) != OK:
			return FAILED
		return OK if DirAccess.copy_absolute(src, dst) == OK else FAILED


static func _copy_dir_recursive(src: String, dst: String) -> Error:
	var dir := DirAccess.open(src)
	if dir == null:
		return FAILED
	if not DirAccess.dir_exists_absolute(dst):
		var parent := dst.get_base_dir()
		if not DirAccess.dir_exists_absolute(parent):
			var err := _copy_dir_recursive(src.get_base_dir(), parent)
			if err != OK:
				return err
		var d := DirAccess.open(parent)
		if d == null:
			return FAILED
		if d.make_dir(dst.get_file()) != OK:
			return FAILED
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n == "." or n == "..":
			n = dir.get_next()
			continue
		var src_child := src.path_join(n)
		var dst_child := dst.path_join(n)
		if dir.current_is_dir():
			var e := _copy_dir_recursive(src_child, dst_child)
			if e != OK:
				dir.list_dir_end()
				return e
		else:
			if DirAccess.copy_absolute(src_child, dst_child) != OK:
				dir.list_dir_end()
				return FAILED
		n = dir.get_next()
	dir.list_dir_end()
	return OK


## List all package ids and manifest paths in the store.
static func list_packages(store_path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var abs_path := globalize(store_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		return out
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var sub := dir.get_next()
	while sub != "":
		if dir.current_is_dir() and sub != "." and sub != "..":
			var manifest_path := abs_path.path_join(sub).path_join("manifest.cfg")
			if FileAccess.file_exists(manifest_path):
				var cfg := ConfigFile.new()
				if cfg.load(manifest_path) == OK:
					var store_root := manifest_path.get_base_dir().get_base_dir()
					out.append({
						"id": sub,
						"name": cfg.get_value("package", "name", sub),
						"version": cfg.get_value("package", "version", ""),
						"store_root": store_root,
						"thumbnail": cfg.get_value("package", "thumbnail", ""),
						"media": cfg.get_value("package", "media", []),
					})
		sub = dir.get_next()
	dir.list_dir_end()
	return out


## Media file extensions allowed for thumbnails and media.
const MEDIA_IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const MEDIA_VIDEO_EXTENSIONS := ["webm", "ogv", "mp4"]


static func is_media_image(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext in MEDIA_IMAGE_EXTENSIONS


static func is_media_video(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext in MEDIA_VIDEO_EXTENSIONS


static func is_media_file(path: String) -> bool:
	return is_media_image(path) or is_media_video(path)


## Load full manifest for a package (includes paths).
static func load_manifest(store_root: String, package_id: String) -> Dictionary:
	var manifest_path := globalize(store_root).path_join(package_id).path_join("manifest.cfg")
	if not FileAccess.file_exists(manifest_path):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return {}
	var paths_var := cfg.get_value("package", "paths", [])
	var paths: PackedStringArray = PackedStringArray(paths_var) if paths_var is Array else PackedStringArray()
	return {
		"id": package_id,
		"name": cfg.get_value("package", "name", package_id),
		"version": cfg.get_value("package", "version", ""),
		"store_root": globalize(store_root),
		"thumbnail": cfg.get_value("package", "thumbnail", ""),
		"media": cfg.get_value("package", "media", []),
		"paths": paths,
	}


## Install (unpack) a package into the project. store_root is the package's store root path.
static func install_package(store_root_globalized: String, package_id: String, project_res_globalized: String, overwrite: bool) -> Dictionary:
	var manifest := load_manifest(store_root_globalized, package_id)
	if manifest.is_empty():
		return {"ok": false, "error": "Manifest not found"}
	var paths: PackedStringArray = manifest.get("paths", PackedStringArray())
	return install_package_selective(store_root_globalized, package_id, project_res_globalized, "", paths, false, overwrite)


## Install selected paths into project. install_subpath is relative to project root (e.g. "addons/MyAddon"). paths_to_install: which manifest paths to copy. ignore_asset_root: strip first path segment from each path when installing.
static func install_package_selective(store_root_globalized: String, package_id: String, project_res_globalized: String, install_subpath: String, paths_to_install: PackedStringArray, ignore_asset_root: bool, overwrite: bool) -> Dictionary:
	var content_dir := store_root_globalized.path_join(package_id).path_join("content")
	var base := project_res_globalized
	if not install_subpath.is_empty():
		base = base.path_join(install_subpath.replace("\\", "/").strip_edges().trim_suffix("/"))
	for rel_path in paths_to_install:
		rel_path = rel_path.replace("\\", "/").strip_edges()
		if rel_path.is_empty():
			continue
		var install_path := rel_path
		if ignore_asset_root:
			var idx := rel_path.find("/")
			if idx >= 0:
				install_path = rel_path.substr(idx + 1)
			else:
				install_path = rel_path.get_file()
		var src := content_dir.path_join(rel_path)
		var dst := base.path_join(install_path)
		if not FileAccess.file_exists(src) and not DirAccess.dir_exists_absolute(src):
			continue
		if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
			if not overwrite:
				return {"ok": false, "error": "File or folder already exists (enable overwrite): %s" % install_path}
		var e := copy_recursive(src, dst)
		if e != OK:
			return {"ok": false, "error": "Failed to copy %s (code %s)" % [install_path, e]}
	return {"ok": true}


## Count how many paths would conflict (already exist) in project. Returns { "count": N, "paths": [...] }.
static func count_conflicts(project_res_globalized: String, install_subpath: String, paths: PackedStringArray, ignore_asset_root: bool) -> Dictionary:
	var base := project_res_globalized
	if not install_subpath.is_empty():
		base = base.path_join(install_subpath.replace("\\", "/").strip_edges().trim_suffix("/"))
	var conflicting: Array = []
	for rel_path in paths:
		rel_path = rel_path.replace("\\", "/").strip_edges()
		if rel_path.is_empty():
			continue
		var install_path := rel_path
		if ignore_asset_root:
			var idx := rel_path.find("/")
			if idx >= 0:
				install_path = rel_path.substr(idx + 1)
			else:
				install_path = rel_path.get_file()
		var dst := base.path_join(install_path)
		if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
			conflicting.append(install_path)
	return {"count": conflicting.size(), "paths": conflicting}


## Ensure package has a media/ directory; return path to it.
static func ensure_media_dir(store_root_globalized: String, package_id: String) -> String:
	var pkg_dir := store_root_globalized.path_join(package_id)
	var media_dir := pkg_dir.path_join("media")
	if not DirAccess.dir_exists_absolute(media_dir):
		var d := DirAccess.open(pkg_dir)
		if d == null:
			return ""
		if d.make_dir("media") != OK:
			return ""
	return media_dir


## Add a media file to a package (copy from source path). Returns the relative path under media/ or empty on failure.
static func add_media_file(store_root_globalized: String, package_id: String, source_absolute_path: String) -> String:
	if not is_media_file(source_absolute_path):
		return ""
	var media_dir := ensure_media_dir(store_root_globalized, package_id)
	if media_dir.is_empty():
		return ""
	var fname := source_absolute_path.get_file()
	var dst := media_dir.path_join(fname)
	if DirAccess.copy_absolute(source_absolute_path, dst) != OK:
		return ""
	var rel_path := "media/%s" % fname
	_append_media_in_manifest(store_root_globalized, package_id, rel_path)
	return rel_path


static func _append_media_in_manifest(store_root_globalized: String, package_id: String, rel_path: String) -> void:
	var manifest_path := store_root_globalized.path_join(package_id).path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return
	var media: Array = Array(cfg.get_value("package", "media", []))
	if rel_path in media:
		return
	media.append(rel_path)
	cfg.set_value("package", "media", media)
	cfg.save(manifest_path)


## Remove a media entry from package and delete the file.
static func remove_media_file(store_root_globalized: String, package_id: String, rel_path: String) -> Error:
	var manifest_path := store_root_globalized.path_join(package_id).path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return FAILED
	var media: Array = Array(cfg.get_value("package", "media", []))
	if rel_path in media:
		media.erase(rel_path)
	cfg.set_value("package", "media", media)
	var thumb := cfg.get_value("package", "thumbnail", "")
	if thumb == rel_path:
		cfg.set_value("package", "thumbnail", "")
	cfg.save(manifest_path)
	var abs_path := store_root_globalized.path_join(package_id).path_join(rel_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	return OK


## Set the package thumbnail to a media path (must be in media list or added).
static func set_package_thumbnail(store_root_globalized: String, package_id: String, rel_path: String) -> Error:
	var manifest_path := store_root_globalized.path_join(package_id).path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return FAILED
	cfg.set_value("package", "thumbnail", rel_path)
	return OK if cfg.save(manifest_path) == OK else FAILED


## Remove a package folder from the store (delete recursively).
static func remove_package(store_root_globalized: String, package_id: String) -> Error:
	var pkg_dir := store_root_globalized.path_join(package_id)
	if not DirAccess.dir_exists_absolute(pkg_dir):
		return ERR_DOES_NOT_EXIST
	return _remove_dir_recursive(pkg_dir)


static func _remove_dir_recursive(path: String) -> Error:
	var dir := DirAccess.open(path)
	if dir == null:
		return FAILED
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n == "." or n == "..":
			n = dir.get_next()
			continue
		var child := path.path_join(n)
		if dir.current_is_dir():
			var e := _remove_dir_recursive(child)
			if e != OK:
				dir.list_dir_end()
				return e
		else:
			if DirAccess.remove_absolute(child) != OK:
				dir.list_dir_end()
				return FAILED
		n = dir.get_next()
	dir.list_dir_end()
	return OK if DirAccess.remove_absolute(path) == OK else FAILED


## Duplicate a package to a new id (copies folder and updates manifest).
static func duplicate_package(store_root_globalized: String, source_id: String, new_id: String) -> Error:
	var src_dir := store_root_globalized.path_join(source_id)
	var dst_dir := store_root_globalized.path_join(new_id)
	if DirAccess.dir_exists_absolute(dst_dir):
		return ERR_ALREADY_EXISTS
	if not DirAccess.dir_exists_absolute(src_dir):
		return ERR_DOES_NOT_EXIST
	var e := _copy_dir_recursive(src_dir, dst_dir)
	if e != OK:
		return e
	var manifest_path := dst_dir.path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return FAILED
	cfg.set_value("package", "id", new_id)
	cfg.set_value("package", "name", cfg.get_value("package", "name", source_id) + " (copy)")
	return OK if cfg.save(manifest_path) == OK else FAILED


## Ensure a directory and all parents exist (absolute path). Returns OK on success.
static func _ensure_dir_absolute(path: String) -> Error:
	if DirAccess.dir_exists_absolute(path):
		return OK
	var parent := path.get_base_dir()
	if parent != path and not parent.is_empty():
		var err := _ensure_dir_absolute(parent)
		if err != OK:
			return err
	var d := DirAccess.open(parent)
	if d == null:
		return FAILED
	return OK if d.make_dir(path.get_file()) == OK else FAILED


## Create package directory layout and write manifest. paths are relative to project res://.
static func create_package(store_path: String, package_id: String, display_name: String, version: String, description: String, paths: PackedStringArray) -> Error:
	var root := globalize(store_path)
	var pkg_dir := root.path_join(package_id)
	var content_dir := pkg_dir.path_join("content")
	if DirAccess.dir_exists_absolute(pkg_dir):
		return ERR_ALREADY_EXISTS
	if _ensure_dir_absolute(root) != OK:
		return FAILED
	var d := DirAccess.open(root)
	if d == null:
		return FAILED
	if d.make_dir(package_id) != OK:
		return FAILED
	if d.change_dir(package_id) != OK:
		return FAILED
	if d.make_dir("content") != OK:
		return FAILED
	var project_root := ProjectSettings.globalize_path("res://")
	for rel_path in paths:
		rel_path = rel_path.replace("\\", "/")
		var src := project_root.path_join(rel_path)
		var dst := content_dir.path_join(rel_path)
		var e := copy_recursive(src, dst)
		if e != OK:
			return e
	var manifest_path := pkg_dir.path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	cfg.set_value("package", "id", package_id)
	cfg.set_value("package", "name", display_name if display_name else package_id)
	cfg.set_value("package", "version", version)
	cfg.set_value("package", "description", description)
	cfg.set_value("package", "paths", Array(paths))
	cfg.set_value("package", "thumbnail", "")
	cfg.set_value("package", "media", [])
	cfg.set_value("package", "created_at", Time.get_datetime_string_from_system())
	if cfg.save(manifest_path) != OK:
		return FAILED
	return OK
