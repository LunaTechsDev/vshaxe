package vshaxe.view.server;

import haxe.ds.ArraySort;
import vshaxe.view.server.Node.HaxeServerContext;
import haxe.display.JsonModuleTypes;

typedef JsonModule = {
	var id:Int;
	var path:JsonModulePath;
	var types:Array<JsonTypePath>;
	var file:String;
	var sign:String;
	var dependencies:Array<JsonModulePath>;
}

typedef JsonServerFile = {
	var file:String;
	var time:Float;
	var pack:String;
	var moduleName:Null<String>;
}

typedef HaxeMemoryResult = {
	var contexts:Array<{
		var context:Null<HaxeServerContext>;
		var size:Int;
		var modules:Array<{var path:String; var size:Int;}>;
	}>;
	var memory:{
		var totalCache:Int;
		var haxelibCache:Int;
		var parserCache:Int;
		var moduleCache:Int;
	}
}

@:nullSafety(Off)
class HaxeServerView {
	final context:ExtensionContext;
	final view:TreeView<Node>;

	public var onDidChangeTreeData:Event<Node> = new EventEmitter<Node>().event;

	public function new(context:ExtensionContext) {
		this.context = context;
		context.registerHaxeCommand(ServerView_CopyNodeValue, copyNodeValue);
		view = window.createTreeView("haxe.server", {treeDataProvider: this, showCollapseAll: true});
		window.registerTreeDataProvider("haxe.server", this);
	}

	public var getParent = function(node:Node) {
		return node.parent;
	}

	public function getTreeItem(?node:Node) {
		return node;
	}

	public function getChildren(?node:Node):ProviderResult<Array<Node>> {
		return if (node == null) {
			[new Node("server", null, ServerRoot), new Node("memory", null, MemoryRoot)];
		} else {
			switch (node.kind) {
				case ServerRoot:
					commands.executeCommand("haxe.runMethod", "server/contexts").then(function(result:Array<HaxeServerContext>) {
						var nodes = [];
						for (ctx in result) {
							nodes.push(new Node(ctx.platform, ctx.desc, Context(ctx)));
						}
						return nodes;
					}, reject -> reject);
				case MemoryRoot:
					commands.executeCommand("haxe.runMethod", "server/memory").then(function(result:HaxeMemoryResult) {
						var nodes = [];
						var kv = [
							{key: "total cache", value: formatSize(result.memory.totalCache)},
							{key: "haxelib cache", value: formatSize(result.memory.haxelibCache)},
							{key: "parser cache", value: formatSize(result.memory.parserCache)},
							{key: "module cache", value: formatSize(result.memory.moduleCache)}
						];
						nodes.push(new Node("overview", null, StringMapping(kv), node));
						for (ctx in result.contexts) {
							var kv = [
								for (m in ctx.modules)
									{
										key: m.path,
										value: formatSize(m.size)
									}
							];
							var name = ctx.context == null ? "?" : '${ctx.context.platform} (${ctx.context.desc})';
							nodes.push(new Node(name, formatSize(ctx.size), StringMapping(kv), node));
						}
						return nodes;
					}, reject -> reject);
				case Context(ctx):
					ArraySort.sort(ctx.defines, (kv1, kv2) -> Reflect.compare(kv1.key, kv2.key));
					[
						new Node('index', "" + ctx.index, Leaf, node),
						new Node('desc', ctx.desc, Leaf, node),
						new Node('signature', ctx.signature, Leaf, node),
						new Node("class paths", null, StringList(ctx.classPaths), node),
						new Node("defines", null, StringMapping(ctx.defines), node),
						new Node("modules", null, ContextModules(ctx), node),
						new Node("files", null, ContextFiles(ctx), node)
					];
				case StringList(strings):
					strings.map(s -> new Node(s, null, Leaf, node));
				case StringMapping(mapping):
					mapping.map(kv -> new Node(kv.key, kv.value, Leaf, node));
				case ContextModules(ctx):
					commands.executeCommand("haxe.runMethod", "server/modules", {signature: ctx.signature}).then(function(result:Array<String>) {
						var nodes = [];
						ArraySort.sort(result, Reflect.compare);
						for (s in result) {
							nodes.push(new Node(s, null, ModuleInfo(ctx, s)));
						}
						return nodes;
					}, reject -> reject);
				case ContextFiles(ctx):
					commands.executeCommand("haxe.runMethod", "server/files", {signature: ctx.signature}).then(function(result:Array<JsonServerFile>) {
						var nodes = result.map(file -> new Node(file.file, null,
							StringMapping([{key: "mtime", value: "" + file.time}, {key: "package", value: file.pack}]), node));
						return nodes;
					}, reject -> reject);
				case ModuleInfo(ctx, path):
					commands.executeCommand("haxe.runMethod", "server/module", {signature: ctx.signature, path: path}).then(function(result:JsonModule) {
						var types = result.types.map(path -> path.typeName);
						ArraySort.sort(types, Reflect.compare);
						var deps = result.dependencies.map(path -> printPath(cast path));
						ArraySort.sort(deps, Reflect.compare);
						return [
							new Node("id", "" + result.id, Leaf, node),
							new Node("path", printPath(cast result.path), Leaf, node),
							new Node("file", result.file, Leaf, node),
							new Node("sign", result.sign, Leaf, node),
							new Node("types", null, StringList(types), node),
							new Node("dependencies", null, StringList(deps), node)
						];
					}, reject -> reject);
				case Leaf:
					[];
			}
		}
	}

	function copyNodeValue(node:Node) {
		function printKv(kv:Array<{key:String, value:String}>) {
			return kv.map(kv -> '${kv.key}=${kv.value}').join(" ");
		}
		var value = switch (node.kind) {
			case StringList(strings): strings.join(" ");
			case StringMapping(mapping): printKv(mapping);
			case Context(ctx):
				var buf = new StringBuf();
				function add(key:String, value:String) {
					buf.add('$key: $value\n');
				}
				add("index", "" + ctx.index);
				add("desc", ctx.desc);
				add("signature", ctx.signature);
				add("platform", ctx.platform);
				add("classPaths", ctx.classPaths.join(" "));
				add("defines", printKv(ctx.defines));
				buf.toString();
			case _: throw false;
		}
		env.clipboard.writeText(value);
	}

	static function printPath(path:JsonTypePath) {
		var buf = new StringBuf();
		if (path.pack.length > 0) {
			buf.add(path.pack.join('.'));
			buf.addChar('.'.code);
		}
		buf.add(path.moduleName);
		if (path.typeName != null) {
			buf.addChar('.'.code);
			buf.add(path.typeName);
		}
		return buf.toString();
	}

	static function formatSize(size:Int) {
		return if (size < 1024) {
			size + " b";
		} else if (size < 1024 * 1024) {
			(size >>> 10) + " Kb";
		} else {
			var size = Std.string(size / (1024 * 1024));
			var offset = size.indexOf(".");
			if (offset < 0) {
				size + " Mb";
			} else {
				size.substr(0, offset + 2) + " Mb";
			}
		}
	}
}
