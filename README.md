# Godot Package Manager

An editor plugin for [Godot 4.6](https://godotengine.org/) that lets you pack project files and folders into a local package store and install them into any project—similar in spirit to Unity’s package workflow, but file-based and fully local.

---

## Features

- **Pack** – Select any files or folders in your project and create a named package. Choose an ID, display name, version, and description.
- **Install** – Install any stored package into the current project. A **Configure before installing** dialog lets you:
  - Change the install folder (e.g. `res://`, `res://addons/MyAddon/`)
  - Include or exclude specific files and folders via checkboxes (Asset Library style)
  - Use **Ignore asset root** to strip the top-level folder when installing
  - See an installation preview and conflict warning
- **Preview** – View package metadata, packed paths, and manage **thumbnails & media** (images and videos) with drag-and-drop and paste.
- **Duplicate** – Copy a package under a new ID.
- **Remove** – Delete a package from the store (with confirmation).
- **Settings** – Configure the package store path (default: `user://package_manager/packs`) and whether to overwrite existing files when installing.

Packages are stored in a configurable location (default per-user, shared across projects on the same machine). No account or server required.

---

## Requirements

- **Godot 4.6** (or compatible 4.x with the same editor APIs)

---

## Installation

1. Clone or download this repository (or copy the `addons/package_manager` folder into your project).
2. Copy the `addons/package_manager` folder into your Godot project’s `addons/` directory.
3. Open **Project → Project Settings → Plugins** and enable **Package Manager**.
4. Use **Package Manager** in the editor top bar (next to Help) → **Open Package Manager**.

---

## Usage

### Opening the manager

- In the editor menu bar, open **Package Manager** → **Open Package Manager**.

### Creating a package

1. Click **Add Package**.
2. Enter a **Package ID** (e.g. `my_asset_pack`), optional display name, version, and description.
3. Click **Add files...** or **Add folder...** and choose what to pack from your project.
4. Click **Create**. The package is saved to your local store.

### Installing a package

1. Select a package in the list.
2. Click **Install**.
3. In **Configure Asset Before Installing**:
   - Use **Change Install Folder** to pick where under `res://` to install (e.g. `res://addons/MyAddon/`).
   - Check or uncheck items in **Contents of the asset** to include or exclude files/folders.
   - Enable **Ignore asset root** to install contents without the package’s top-level folder.
   - Check the **Installation preview** and conflict message.
4. Click **Install** in the dialog to perform the install.

### Thumbnails and media

- Select a package and click **Preview**.
- In the preview panel, use the **Thumbnail & media** section to add images or videos by drag-and-drop, paste (file paths in clipboard), or **Add media...**.
- Use **Set as thumbnail** or **Remove** on each item as needed.

### Other actions

- **Refresh** – Rescan the package store.
- **Settings** – Set the store path and overwrite behavior.
- **Duplicate** – Create a copy of the selected package with a new ID.
- **Remove** – Delete the selected package from the store (with confirmation).

---

## Package store layout

- **Default path**: `user://package_manager/packs/` (persistent per OS user; shared across projects on the same machine).
- **Configurable** in Settings (e.g. custom or network path).

Each package is a folder under the store:

```
{store}/{package_id}/
  manifest.cfg    # id, name, version, paths, thumbnail, media list
  content/        # copied project files and folders
  media/          # thumbnails and media (images/videos)
```

---

## Using the plugin in multiple projects

Godot does not support “global” editor plugins. You can still use one copy of the addon across projects in these ways:

| Method | Description |
|--------|-------------|
| **Per-project** | Copy `addons/package_manager` into each project and enable the plugin. |
| **Project template** | Create a Godot project template that includes the addon; new projects from that template get the manager by default. |
| **Symlink / junction** | Install the addon once, then create a symlink (or junction on Windows) from each project’s `addons/package_manager` to that copy. All projects use the same files. |
| **Global-project** | Use a framework like [godot-global-project](https://github.com/dugramen/godot-global-project) so a single global project provides editor plugins to every project. |

### Symlink examples

**Windows (Command Prompt as Administrator):**

```bat
mklink /J "C:\Path\To\YourProject\addons\package_manager" "C:\Path\To\ThisRepo\addons\package_manager"
```

**macOS / Linux:**

```bash
ln -s /path/to/this/repo/addons/package_manager /path/to/your_project/addons/package_manager
```

---

## License

This project is provided as-is. Use it under the same terms as your project, or under the MIT License if no other license is specified. See the [LICENSE](LICENSE) file in the repository if present.

---

## Contributing

Contributions are welcome. Open an issue or a pull request on the repository.
