package haxeshim;

using haxe.io.Path;
using sys.io.File;
using sys.FileSystem;
using StringTools;
using tink.CoreApi;

class Resolver {
  
  var cwd:String;
  var scopeDir:String;
  var mode:LibResolution;
  var ret:Array<String>;
  var libs:Array<String>;
  var defaults:Map<String, String>;
  
  public function new(cwd, scopeDir, mode, defaults) {
    this.cwd = cwd;
    this.scopeDir = scopeDir;
    this.mode = mode;
    this.defaults = defaults;
  }
  
  function interpolate(s:String) {
    if (s.indexOf("${") == -1)
      return s;
      
    var ret = new StringBuf(),
        pos = 0;
        
    while (pos < s.length)
      switch s.indexOf("${", pos) {
        case -1:
          ret.addSub(s, pos);
          break;
        case v:
          ret.addSub(s, pos, v - pos);
          var start = v + 2;
          var end = switch s.indexOf('}', start) {
            case -1:
              throw 'unclosed interpolation in $s';
            case v: v;
          }
          
          var name = s.substr(start, end - start);
          
          ret.add(
            switch Sys.getEnv(name) {
              case '' | null:
                switch defaults[name] {
                  case null:
                    throw 'unknown variable $name';
                  case v: v;
                }
              case v: v;
            }
          );
          
          pos = end + 1;
      }
    
    return ret.toString();
  }
  
  public function resolve(args:Array<String>, haxelib:Array<String>->Array<String>) {
    
    this.ret = [];
    this.libs = [];
    
    process(args);
    
    return ret.concat(haxelib(libs));
  }
  
  function resolveInScope(lib:String) 
    return switch '$scopeDir/.scopedHaxeLibs/$lib.hxml' {
      case notFound if (!notFound.exists()):
        Failure('Cannot resolve `-lib $lib` because file $notFound is missing');
      case f: 
        processHxml(f);
        Success(Noise);
    }
    
  function processHxml(file:String) {
    process(parseLines(file.getContent()));
  }
  
  static public function parseLines(source:String, ?normalize:String->Array<String>) {
    if (normalize == null)
      normalize = function (x) return [x];
      
    var ret = [];
    
    for (line in source.split('\n').map(StringTools.trim))
      switch line.charAt(0) {
        case null:
        case '-':
          switch line.indexOf(' ') {
            case -1:
              ret.push(line);
            case v:
              ret.push(line.substr(0, v));
              ret.push(line.substr(v).trim());
          }
        case '#':
        default:
          for (a in normalize(line))
            ret.push(a);
      }
    
    return ret;
  }
  
  function process(args:Array<String>) {
    var i = 0,
    max = args.length;
          
    while (i < max)
      switch args[i++].trim() {
        case '':
        case '-cp':
          
          ret.push('-cp');
          ret.push(absolute(interpolate(args[i++])));
          
        case '-lib':
          
          var lib = args[i++];
          
          switch mode {
            case Haxelib:
              
              libs.push(lib);
              
            case Scoped:
              
              if (lib.indexOf(':') == -1)
                resolveInScope(lib).sure();
              else
                throw 'Invalid `-lib $lib`. Version specification not supported in scoped mode';
                
            case Mixed:
              if (lib.indexOf(':') != -1 || !resolveInScope(lib).isSuccess())
                libs.push(lib);
          }
          
        case hxml if (hxml.endsWith('.hxml')):
          
          processHxml(absolute(hxml));
          
        case v:
          ret.push(v);
      }
  }
  
  function absolute(path:String)
    return 
      if (path.isAbsolute()) path;
      else Path.join([cwd, path]);
  
  static function removeComments(line:String)
    return 
      switch line.indexOf('#') {
        case -1: line;
        case v: line.substr(0, v);
      }
  
}