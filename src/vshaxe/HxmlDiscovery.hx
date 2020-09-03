package vshaxe;

import haxe.io.Path;

class HxmlDiscovery {
	public static inline final DiscoveredFilesKey = new MementoKey<Array<String>>("haxe.hxmlDiscoveryFiles");

	public var files(default, null):Array<String>;
	public var onDidChangeFiles(get, never):Event<Void>;

	final folder:WorkspaceFolder;
	final mementos:WorkspaceMementos;
	final didChangeFilesEmitter:EventEmitter<Void>;
	final fileWatcher:FileSystemWatcher;

	inline function get_onDidChangeFiles()
		return didChangeFilesEmitter.event;

	public function new(folder, mementos) {
		this.folder = folder;
		this.mementos = mementos;
		didChangeFilesEmitter = new EventEmitter();
		files = mementos.getDefault(folder, DiscoveredFilesKey, []);

		final globConfig = workspace.getConfiguration('haxe').get('hxmlGlobPattern');
		final globPattern = globConfig == null ? '*.hxml' : globConfig;

		final pattern = new RelativePattern(folder, globPattern);
		fileWatcher = workspace.createFileSystemWatcher(pattern, false, true, false);
		fileWatcher.onDidCreate(uri -> {
			files.push(pathRelativeToRoot(uri));
			onFilesChanged();
		});
		fileWatcher.onDidDelete(uri -> {
			files.remove(pathRelativeToRoot(uri));
			onFilesChanged();
		});

		workspace.findFiles(pattern).then(files -> {
			var foundFiles = [];
			if (files != null) {
				foundFiles = files.map(uri -> pathRelativeToRoot(uri)).filter(path -> Path.withoutDirectory(path) != "extraParams.hxml");
			}

			if (!this.files.equals(foundFiles)) {
				this.files = foundFiles;
				onFilesChanged();
			}
		});
	}

	inline function onFilesChanged() {
		mementos.set(folder, DiscoveredFilesKey, files);
		didChangeFilesEmitter.fire();
	}

	inline function pathRelativeToRoot(uri:Uri):String {
		return vshaxe.helper.PathHelper.relativize(uri.fsPath, folder.uri.fsPath);
	}

	public function dispose() {
		fileWatcher.dispose();
		didChangeFilesEmitter.dispose();
	}
}
